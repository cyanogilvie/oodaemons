# vim: ft=tcl foldmethod=marker foldmarker=<<<,>>> ts=4 shiftwidth=4

cflib::singleton create oodaemons::mimetypes {
	variable {*}{
		mimetypes
		mimetypes_fn
	}

	constructor {args} { #<<<
		set settings	[dict merge {
			-mimetypes_fn	"/etc/mime.types"
		} $args]

		dict for {k v} $settings {
			set [string range $k 1 end] $v
		}

		if {![file readable $mimetypes_fn]} {
			error "Specified mimetypes file is not readable: \"$mimetypes_fn\""
		}

		set mimetypes		[dict create]
		set mimetypes_raw	[cflib::readfile $mimetypes_fn]

		?? {puts stderr "Parsing $mimetypes_fn"}
		foreach line [split $mimetypes_raw \n] {
			set line	[string trim $line]
			if {$line eq ""} continue
			if {[string index $line 0] eq "#"} continue
			set exts	[lassign $line type]
			if {[llength $exts] == 0} continue

			foreach ext $exts {
				if {[dict exists $mimetypes $ext]} {
					?? {puts stderr "Redefinition of mimetype for \"$ext\", was \"[dict get $mimetypes $ext]\", ignoring new type: \"$type\""}
					continue
				}
				dict set mimetypes $ext $type
			}
		}
	}

	#>>>
	method for_path {path args} { #<<<
		set ext	[string range [file extension $path] 1 end]

		if {[dict exists $mimetypes $ext]} {
			return [dict get $mimetypes $ext]
		} else {
			if {[llength $args] > 0} {
				return	[lindex $args 0]
			} else {
				throw {no_mimetype} "No mimetype defined for \"$ext\""
			}
		}
	}

	#>>>
}
