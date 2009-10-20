# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

oo::class create oodaemons::json {
	variable {*}{
		doc
		root
	}

	constructor {} { #<<<
		package require tdom

		set doc		[dom createDocument json]
		set root	[$doc documentElement]
	}

	#>>>
	destructor { #<<<
		if {[info exists doc]} {
			$doc delete
			unset doc
		}
	}

	#>>>

	method parse {json_txt} { #<<<
		if {[string match "/\\\**\\\*/" $json_txt]} {
			set json_txt	[string range $json_txt 2 end-2]
		}

		set remaining	[my _parse_value $root $json_txt]

		if {$remaining ne ""} {
			error "Trailing garbage: ($remaining)"
		}
	}

	#>>>
	method root {} { #<<<
		return $root
	}

	#>>>
	method serialize {} { #<<<
		set parts	{}
		foreach child [$root childNodes] {
			lappend parts	[my _processnode $child]
		}

		join $parts ,
	}

	#>>>
	method as_dict {{node ""}} { #<<<
		if {$node eq ""} {
			set node	[$root firstChild]
		}
		set res	{}

		switch -- [$node nodeName] {
			list {
				foreach elem [$node childNodes] {
					lappend res [my as_dict $elem]
				}
			}

			object {
				foreach elem [$node childNodes] {
					dict set res [$elem @name] [my as_dict $elem]
				}
			}

			string {
				set res	[$node text]
			}

			number {
				set res	[$node text]
			}

			true {
				set res	"true"
			}

			false {
				set res	"false"
			}

			null {
				set res	""
			}

			default {
				error "Invalid type: ([$node nodeName])"
			}
		}

		return $res
	}

	#>>>

	method _quote_string {in} { #<<<
		upvar [self class]::map map
		if {![info exists map]} {
			set map [dict create \
					"\\/"	"\\/" \
					"\\b"	"\\b" \
					"\\f"	"\\f" \
					"\\n"	"\\n" \
					"\\r"	"\\r" \
					"\\t"	"\\t" \
					"\b"	"\\b" \
					"\f"	"\\f" \
					"\t"	"\\t" \
					"\n"	"\\n" \
					"\r"	"\\r" \
					"\\"	"\\\\" \
					"\""	"\\\"" \
			]
		}
		set quoted	[string map $map $in]
		return "\"$quoted\""
	}

	#>>>
	method _process_list {node} { #<<<
		set parts	{}

		foreach child [$node childNodes] {
			lappend parts	[my _processnode $child]
		}

		return "\[[join $parts ,]\]"
	}

	#>>>
	method _process_object {node} { #<<<
		set parts	{}
		foreach child [$node childNodes] {
			if {![$child hasAttribute name]} {
				error "Object child does not have name attribute"
			}

			set value	[my _processnode $child]

			lappend parts	"[my _quote_string [$child @name]]:$value"
		}
		return "{[join $parts ,]}"
	}

	#>>>
	method _processnode {node} { #<<<
		set nodeName	[$node nodeName]
		switch -- $nodeName {
			object {
				set value	[my _process_object $node]
			}

			string {
				set value	[my _quote_string [$node text]]
			}

			number {
				set raw		[$node text]
				if {
					![string is double -strict $raw] &&
					![string is digit -strict $raw]
				} {
					error "Numberic value is invalid: ($raw)"
				}
				set value	$raw
			}

			list {
				set value	[my _process_list $node]
			}

			true - false - null {
				set value	$nodeName
			}

			default {
				error "Invalid node type: ($nodeName)"
			}
		}

		return $value
	}

	#>>>
	method _parse_value {parent json_fragment {name ""}} { #<<<
		set json_fragment	[string trim $json_fragment]
		switch -glob -- $json_fragment {
			"\"*" {
				set json_fragment	[my _parse_string $parent $json_fragment $name]
			}

			"\{*" {
				set json_fragment	[my _parse_object $parent $json_fragment $name]
			}

			"\\\[*" {
				set json_fragment	[my _parse_list $parent $json_fragment $name]
			}

			"true*" - "false*" {
				set json_fragment	[my _parse_boolean $parent $json_fragment $name]
			}

			"null*" {
				set json_fragment	[my _parse_null $parent $json_fragment $name]
			}

			default {
				if {[string index $json_fragment 0] in {
					- 0 1 2 3 4 5 6 7 8 9
				}} {
					set json_fragment	[my _parse_number $parent $json_fragment $name]
				} else {
					error "Bad fragment: ($json_fragment)"
				}
			}
		}

		return $json_fragment
	}

	#>>>
	method _parse_string {parent json_fragment {name ""}} { #<<<
		set p	1

		set stringval		""
		set fragment_length	[string length $json_fragment]

		while {$p < $fragment_length} {
			set char	[string index $json_fragment $p]
			switch -- $char {
				"\\" {
					if {$p == $fragment_length - 1} {
						error "Bad backquote escape at end of string: ($json_fragment)"
					}

					incr p

					set qchar	[string index $json_fragment $p]

					if {$qchar in {
						b
						f
						n
						r
						t
					}} {
						append stringval	[subst "\\$qchar"]
					} elseif {$qchar eq "u"} {
						# TODO: handle unicode \xHHHH, where H is a hex digit
						set hexdigits	[string range $json_fragment $p+1 $p+4]
						if {
							![string is xdigit -strict $hexdigits] ||
							[string length $hexdigits] != 4
						} {
							error "Invalid Hex unicode encoding: ($hexdigits)"
						}
						append stringval	"\u$hexdigits"
					} else {
						append stringval	$qchar
					}
				}

				"\"" {
					set stringnode	[$doc createElement string]
					if {$name ne ""} {
						$stringnode setAttribute name $name
					}
					$stringnode appendChild [$doc createTextNode $stringval]
					$parent appendChild $stringnode

					incr p
					return [string range $json_fragment $p end]
				}

				default {
					append stringval	$char
				}
			}

			incr p
		}

		error "Unterminated string: ($json_fragment)"
	}

	#>>>
	method _parse_number {parent json_fragment {name ""}} { #<<<
		set number	""
		set p		0
		if {[string index $json_fragment $p] eq "-"} {
			append number "-"
			incr p
		}
		if {[string index $json_fragment $p] eq "0"} {
			if {[string index $json_fragment $p+1] eq "."} {
				set number	"0."
				incr p 2
			} else {
				error "Cannot have octal formatted numbers: ($json_fragment)"
			}
		}
		lassign [my _parse_digits $json_fragment] digits json_fragment
		append number	$digits

		if {[string index $json_fragment 0] eq "."} {
			set json_fragment	[string range $json_fragment 1 end]
			lassign [my _parse_digits $json_fragment] digits json_fragment
			append number ".$digits"
		}

		if {[string tolower [string index $json_fragment 0]] eq "e"} {
			append number	"e"
			set p	1
			if {[string index $json_fragment $p] eq "+"} {
				incr p
			} elseif {[string index $json_fragment $p] eq "-"} {
				append number	"-"
				incr p
			}

			lassign [my _parse_digits $json_fragment] digits json_fragment
			append number $digits
		}

		set thisnode		[$doc createElement number]
		$thisnode appendChild [$doc createTextNode $number]
		if {$name ne ""} {
			$thisnode setAttribute name $name
		}
		$parent appendChild $thisnode
		return [string trim $json_fragment]
	}

	#>>>
	method _parse_object {parent json_fragment {name ""}} { #<<<
		set json_fragment	[string trim [string range $json_fragment 1 end]]
		set thisnode		[$doc createElement object]
		if {$name ne ""} {
			$thisnode setAttribute name $name
		}
		$parent appendChild $thisnode

		while {[string length $json_fragment] > 0} {
			lassign [my _parse_label $json_fragment] label json_fragment

			set json_fragment	[my _parse_value $thisnode $json_fragment $label]
			set json_fragment	[string trim $json_fragment]

			if {[string index $json_fragment 0] eq "\}"} {
				set json_fragment	[string range $json_fragment 1 end]
				return $json_fragment
			}

			if {[string index $json_fragment 0] eq ","} {
				set json_fragment	[string trim [string range $json_fragment 1 end]]
			} else {
				break
			}
		}

		error "Unterminated object: ($json_fragment)"
	}

	#>>>
	method _parse_list {parent json_fragment {name ""}} { #<<<
		set json_fragment	[string trim [string range $json_fragment 1 end]]
		set thisnode		[$doc createElement list]
		if {$name ne ""} {
			$thisnode setAttribute name $name
		}
		$parent appendChild $thisnode

		while {[string length $json_fragment] > 0} {
			if {[string index $json_fragment 0] eq "\]"} {
				set json_fragment	[string range $json_fragment 1 end]
				return $json_fragment
			}

			set json_fragment	[my _parse_value $thisnode $json_fragment]
			set json_fragment	[string trim $json_fragment]

			if {[string index $json_fragment 0] eq "\]"} {
				set json_fragment	[string range $json_fragment 1 end]
				return $json_fragment
			}

			if {[string index $json_fragment 0] eq ","} {
				set json_fragment	[string trim [string range $json_fragment 1 end]]
			} else {
				break
			}
		}

		error "Unterminated list: ($json_fragment)"
	}

	#>>>
	method _parse_boolean {parent json_fragment {name ""}} { #<<<
		set json_fragment	[string trim $json_fragment]
		switch -glob -- $json_fragment {
			"true*" {
				set thisnode		[$doc createElement true]
				if {$name ne ""} {
					$thisnode setAttribute name $name
				}
				$parent appendChild $thisnode

				return [string trim [string range $json_fragment 4 end]]
			}

			"false*" {
				set thisnode		[$doc createElement false]
				if {$name ne ""} {
					$thisnode setAttribute name $name
				}
				$parent appendChild $thisnode

				return [string trim [string range $json_fragment 5 end]]
			}

			default {
				error "Invalid boolean value: ($json_fragment)"
			}
		}
	}

	#>>>
	method _parse_null {parent json_fragment {name ""}} { #<<<
		set json_fragment	[string trim $json_fragment]
		switch -glob -- $json_fragment {
			"null*" {
				set thisnode		[$doc createElement null]
				if {$name ne ""} {
					$thisnode setAttribute name $name
				}
				$parent appendChild $thisnode

				return [string trim [string range $json_fragment 4 end]]
			}

			default {
				error "Invalid null value: ($json_fragment)"
			}
		}
	}

	#>>>
	method _parse_label {json_fragment} { #<<<
		set json_fragment	[string trim $json_fragment]

		set label	""
		set p		0
		set fragment_length	[string length $json_fragment]
		if {[string index $json_fragment 0] eq "\""} {
			# Parse as quoted string
			set p	1
			while {$p < $fragment_length} {
				set char	[string index $json_fragment $p]
				switch -- $char {
					"\\" {
						if {$p == $fragment_length - 1} {
							error "Bad backquote escape at end of label: ($json_fragment)"
						}

						incr p
						append stringval	[string index $json_fragment $p]
					}

					"\"" {
						incr p
						set json_fragment	[string trim [string range $json_fragment $p end]]
						if {[string index $json_fragment 0] ne ":"} {
							error "Expecting \":\": ($json_fragment)"
						}
						set json_fragment	[string trim [string range $json_fragment 1 end]]
						return [list $label $json_fragment]
					}

					default {
						append label	$char
					}
				}

				incr p
			}

			error "Unterminated label: ($json_fragment)"
		} else {
			# Parse as bareword
			# Do backquoting here?
			while {$p < $fragment_length} {
				set char	[string index $json_fragment $p]
				if {$char eq ":"} {
					incr p
					set json_fragment	[string trim [string range $json_fragment $p end]]
					return [list $label $json_fragment]
				}
				# TODO: does space terminate a bareword?
				append label	$char
			}

			error "Unterminated label: ($json_fragment)"
		}
	}

	#>>>
	method _parse_digits {json_fragment} { #<<<
		set digits			""
		set p				0
		set fragment_length	[string length $json_fragment]
		while {$p < $fragment_length} {
			set char	[string index $json_fragment $p]
			if {[string is digit -strict $char]} {
				append digits	$char
			} else {
				set json_fragment	[string trim [string range $json_fragment $p end]]
				return [list $digits $json_fragment]
			}
			incr p
		}
	}

	#>>>
	method log {lvl {msg ""} args} { #<<<
		puts stderr $msg
	}

	unexport log
	#>>>
}


