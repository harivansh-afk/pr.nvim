if exists('b:current_syntax')
  finish
endif

syntax match prLogStamp /^\d\{4}-\d\d-\d\dT[0-9:.]\+Z / conceal
syntax match prLogMarker /\%(##\)\?\[\a\+\]/ contained conceal
syntax match prLogGroup /##\[group\].*/ contains=prLogMarker
syntax match prLogEnd /##\[endgroup\].*/ contains=prLogMarker
syntax match prLogError /##\[error\].*/ contains=prLogMarker
syntax match prLogWarning /##\[warning\].*/ contains=prLogMarker
syntax match prLogNotice /##\[notice\].*/ contains=prLogMarker
syntax match prLogCommand /\%(##\)\?\[command\].*/ contains=prLogMarker

highlight default link prLogGroup Title
highlight default link prLogError DiagnosticError
highlight default link prLogWarning DiagnosticWarn
highlight default link prLogNotice DiagnosticInfo
highlight default link prLogCommand Directory

let b:current_syntax = 'prlog'
