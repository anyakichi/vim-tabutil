" Tab management utility
" Maintainer: INAJIMA Daisuke <inajima@sopht.jp>
" Version: 0.1
" License: MIT License

let s:save_cpo = &cpo
set cpo&vim

let s:tab_stack = []

function! s:any(list, item)
    for i in a:list
	if type(i) == type(a:item) && i == a:item
	    return 1
	endif
    endfor
    return 0
endfunction

function! s:split(mod)
    if bufnr('#') == -1
	return
    endif

    let bufnr = bufnr('%')
    buffer #
    execute a:mod 'sbuffer' bufnr
endfunction

" Move current buffer to a new tab (like CTRL-W_T).
" If a tab has only one window, move the buffer to a new tab and go back to
" buffer # in original window.
function! tabutil#split()
    if winnr('$') > 1
	wincmd T
    else
	call s:split('tab')
    endif
endfunction

" Move current buffer to new window.
function! tabutil#wsplit()
    call s:split('')
endfunction

" Like tabutil#wsplit but vertical.
function! tabutil#vsplit()
    call s:split('vertical')
endfunction

" Save window layout.
function! tabutil#savewinlayout()
    let session = {'file': tempname(), 'restcmd': winrestcmd(),
    \		   'winnr': winnr(), 'buflist': []}

    1wincmd w
    for _ in range(tabpagenr('$'))
	let buf = {'bufnr': winbufnr(0), 'view': winsaveview()}
	call add(session['buflist'], buf)
	wincmd w
    endfor

    let ssop_save = &sessionoptions
    set sessionoptions=blank,help
    execute 'mksession!' session['file']
    let &sessionoptions = ssop_save

    return session
endfunction

" Restore window layout.
function! tabutil#restwinlayout(session)
    let split_save = [&splitbelow, &splitright]

    " Restore window layout from session file
    let lines = readfile(a:session['file'])
    for i in range(0, len(lines) - 1)
	if lines[i] =~ '^set splitbelow'
	    break
	endif
    endfor
    for i in range(i - 1, len(lines) - 1)
	if lines[i] =~ '^set winheight'
	    break
	endif
	execute lines[i]
    endfor

    " Resize windows
    execute a:session['restcmd']

    " Open buffers
    1wincmd w
    for buf in a:session['buflist']
	execute 'buffer' buf['bufnr']
	call winrestview(buf['view'])
	wincmd w
    endfor

    " Change current buffer
    execute a:session['winnr'] . 'wincmd w'

    " Clean up
    call delete(a:session['file'])
    let [&splitbelow, &splitright] = split_save
endfunction

" Close a tab and push the tab state to tab stack.
" Closing tab can be restored later by tabutil#undo().
function! tabutil#close()
    if tabpagenr('$') == 1
	echo 'Already only one tab'
	return
    endif

    let tab_state = {'tabnr': tabpagenr(), 'session': tabutil#savewinlayout()}
    call add(s:tab_stack, tab_state)
    tabclose
endfunction

" Close all other tabs and the states of closing tabs are pushed to tab stack.
function! tabutil#only()
    for tabnr in range(tabpagenr('$'), tabpagenr() + 1, -1)
	execute 'tabnext' tabnr
	call tabutil#close()
    endfor
    for tabnr in range(tabpagenr() - 1, 1, -1)
	execute 'tabnext' tabnr
	call tabutil#close()
    endfor
endfunction

" Restore the last closed tab.
function! tabutil#undo()
    try
	let tab_state = remove(s:tab_stack, -1)
    catch
	echo 'No closed tab'
	return
    endtry

    tab split
    call tabutil#restwinlayout(tab_state['session'])
    execute 'silent! tabmove' (tab_state['tabnr'] - 1)
endfunction

" Restore all closed tabs.
function! tabutil#undoall()
    while len(s:tab_stack) > 0
	call tabutil#undo()
    endwhile
endfunction

" Move a tab.
function! tabutil#move(count)
    if has('patch-7.3.591')
        if a:count =~# '^[-+]'
            execute 'tabmove' a:count
        else
            execute 'tabmove' '+' . a:count
        endif
    else
        let pos = (tabpagenr() + a:count - 1 + tabpagenr('$')) % tabpagenr('$')
        execute 'tabmove' pos
    endif
endfuncti

" Open a buffer in new tab or jump to the buffer in another tab.
function! tabutil#buffer(count)
    let swb_save = &switchbuf
    set switchbuf=usetab
    execute 'tab sbuffer' a:count
    let &switchbuf = swb_save
endfunction

" Open the next buffer in new tab or jump to the buffer in another tab.
function! tabutil#bnext(count)
    let swb_save = &switchbuf
    set switchbuf=usetab
    execute 'tab sbnext' a:count
    let &switchbuf = swb_save
endfunction

" Open the previous buffer in new tab or jump to the buffer in another tab.
function! tabutil#bprevious(count)
    let swb_save = &switchbuf
    set switchbuf=usetab
    execute 'tab sbprevious' a:count
    let &switchbuf = swb_save
endfunction

" Close duplicate tabs and open hidden buffers in new tabs.
function! tabutil#reorganize()
    let tablists = []
    let bufs = {}

    let tabnr = 1
    while type(tabpagebuflist(tabnr)) == type([])
	let tablist = tabpagebuflist(tabnr)

	if s:any(tablists, tablist)
	    execute 'tabclose' tabnr
	    continue
	endif

	call add(tablists, tablist)

	for i in tablist
	    let bufs[i] = 1
	endfor

	let tabnr += 1
    endwhile

    silent! tablast

    for bufnr in range(1, bufnr('$'))
	if !has_key(bufs, bufnr) && buflisted(bufnr)
	    execute 'tab sbuffer' bufnr
	endif
    endfor

    tabfirst
endfunction

" Like tabutil#reorganize but one buffer per one tab.
function! tabutil#reorganize1()
    let bufnrs = []

    for tabnr in range(1, tabpagenr('$'))
	call extend(bufnrs, tabpagebuflist(tabnr))
    endfor

    tabonly

    let bufs = {}
    for bufnr in bufnrs
	if !has_key(bufs, bufnr)
	    execute 'tab sbuffer' bufnr
	    let bufs[bufnr] = 1
	endif
    endfor

    for bufnr in range(1, bufnr('$'))
	if !has_key(bufs, bufnr) && buflisted(bufnr)
	    execute 'tab sbuffer' bufnr
	endif
    endfor

    tabfirst
    tabclose
endfunction

let &cpo = s:save_cpo
