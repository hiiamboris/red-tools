Red[
    Title: "Various function! related tools"
    Author: "Boleslav Březovský"
    Note: {
For details about these functions, see my articles:

`apply`, `ufc` - http://red.qyz.cz/apply-and-ufcs.html
`dispatcher`   - http://red.qyz.cz/pattern-matching.html
}
]

actions: has [
    "Return block of all actions"
    result
][
    result: []
    if empty? result [
        result: collect [
            foreach word words-of system/words [
                if action? get/any word [keep word]
            ]
        ]
    ]
    result
]

op: func [
    "Defines op! with given spec and body"
    spec [block!]
    body [block!]
][
    make op! func spec body
]

; --- get arity and refinements ------------------------------------------------

arity?: func [
    "Return function's arity" ; TODO: support for lit-word! and get-word! ?
    fn [any-function!]  "Function to examine"
    /local result count name count-rule refinement-rule append-name
][
    result: copy []
    count: 0
    name: none
    append-name: quote (repend result either name [[name count]][[count]]) 
    count-rule: [
        some [
            word! (count: count + 1)
        |   ahead refinement! refinement-rule
        |   skip
        ]
    ] 
    refinement-rule: [
        append-name
        set name refinement!
        (count: 0)
        count-rule
    ]
    parse spec-of :fn count-rule
    do append-name
    either find result /local [
        head remove/part find result /local 2
    ][result]
]

refinements?: func [
    "Return block of refinements for given function"
    fn      [any-function!] "Function to examine"
    /local value
][
    parse spec-of :fn [
        collect [some [set value refinement! keep (to word! value) | skip]]
    ]
]

; --- unified function call syntax ---------------------------------------------

ufcs: func [
    "Apply functions to given series"
    series  [series!]       "Series to manipulate"
    dialect [block!]        "Block of actions and arguments, without first argument (series defined above)"
    /local result action args code arity refs ref-stack refs?
][
    result: none
    code: []
    until [
        ; do some preparation
        clear code
        action: take dialect
        arity: arity? get action
        args: arity/1 - 1
        refs: refinements? get action
        ref-stack: clear []
        refs?: false
        unless zero? args [append ref-stack take dialect]
        ; check for refinements
        while [find refs first dialect][
            refs?: true
            ref: take dialect
            either path? action [
                append action ref 
            ][
                action: make path! reduce [action ref]
            ] 
            unless zero? select arity ref [
                append ref-stack take dialect 
            ]
        ]
        ; put all code together
        append/only code action 
        append/only code series
        unless empty? ref-stack [append code ref-stack]
        series: do code
        empty? dialect
    ]
    series
]

ufc: function [
    "Apply functions to given series"
    data    [series!] "Series to manipulate"
    dialect [block!]  "Block of actions and arguments, without first argument (series defined above)"
][
    foreach [cmd args] dialect [
        data: apply get cmd head insert/only args data
    ]
    data
]

; --- apply function -----------------------------------------------------------

apply: func [
    "Apply a function to a block of arguments"
    fn      [any-function!] "Function value to apply"
    args    [block!]        "Block of arguments (to quote refinement use QUOTE keyword)"
    /local refs vals val
][
    refs: copy []
    vals: copy []
    set-val: [set val skip (append/only vals val)]
    parse args [
        some [
            'quote set-val
        |   set val refinement! (append refs to word! val)
        |   set-val
        ]
    ]
    do compose [(make path! head insert refs 'fn) (vals)]
]

map: func [
	"Apply code over block of values"
	data
	code
	/local f
][
	data: copy data
	f: get take code
	forall data [
		data/1: apply :f compose [(first data) (code)]
	]
	data
]

map-each: func [
    'word
    series
    code
][
    collect [
        until [
            set :word first series
            keep do code
            series: next series
            tail? series
        ]
    ]
]

; --- dispatch function --------------------------------------------------------

dispatcher: func [
	"Return dispatcher function that can be extended with DISPATCH"
	spec [block!] "Function specification"
][
	func spec [
		case []
	]
]

dispatch: func [
	"Add new condition and action to DISPATCHER function"
	dispatcher  [any-function!] "Dispatcher function to use"
	cond		[block! none!]	"Block of conditions to pass or NONE for catch-all condition (forces /RELAX)" 
	body		[block! none!]  "Action to do when condition is fulfilled or NONE for removing rule"
	/relax						"Add condition to end of rules instead of beginning"
	/local this cases mark penultimo
][
	cases: second body-of :dispatcher
    penultimo: back back tail cases
    unless equal? true first penultimo [penultimo: tail cases]
    if cond [bind cond :dispatcher]
    if body [bind body :dispatcher]
	this: compose/deep [all [(cond)] [(body)]]
	case [
        all [not cond not body not empty? penultimo][remove/part penultimo 2]   ; remove catch-all rule (if exists)
        all [not body mark: find/only cases cond][remove/part back mark 3]      ; remove rule (if exists)
        all [not cond true = first penultimo][change/only next penultimo body]  ; change catch-all rule (if exists)
        not cond                            [repend cases [true body]]          ; add catch-all rule
		mark: find/only cases cond 	        [change/part back mark this 3]      ; change existing rule (if exists)
		relax 				    	        [insert penultimo this]             ; add new rule to end
		'default 				            [insert cases this]                 ; add new rule to beginning
	]
	:dispatcher
]

; --- function constructors --------------------------------------------

dfunc: func [
    "Define function with default values for local words"
    spec
    body
][
    ; format for default values is [set-word: value] after /local refinement
    ; it's possible to mix normal words (without default value) and set-words
    local: copy []
    locals: copy #()
    if mark: find spec /local [
        parse next mark [
            some [
                set word set-word!
                set value skip (
                    append local to word! word
                    locals/:word: value
                )
            |   set word word! (append local word)
            ]
        ]
        remove/part mark length? mark
        append spec compose [/local (local)]
        foreach word words-of locals [
            insert body reduce [to set-word! word locals/:word]
        ]
    ]
    func spec body
]

fce: func [
	"The ultimate function constructor" ; right now supports /local only
	spec [block!]
	body [block!]
	/local local-mark locals locs expose? body-rule word length
][
	; get local words defined in function specs
	parse spec [
		any [
			ahead /local local-mark: skip
			copy locals to [refinement! | issue! | end]
		|	remove #expose (expose?: true)
		|	skip
		]
	]
	unless locals [locals: copy []]
	locs: clear []
	; get local words defined in function body using local
	parse body body-rule: [
		some [
			ahead [/local [set-word! | word!]]
			remove skip set word skip (append locs to word! word)
		|	ahead [block! | paren!] into body-rule
		|	skip
		]
	]
	length: length? locals
	either expose? [
		remove/part local-mark 1 + length
	][
		append locals locs
		locals: unique locals
		either local-mark [
			change/part next local-mark locals length
		][
			append spec head insert locals /local
		]
	]
	func spec body
]
