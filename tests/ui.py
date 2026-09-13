"""Real attached Neovim UI integration tests. Requires pynvim (test-only)."""
import json
import faulthandler
import os
import pathlib
import time

import pynvim

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / ".test-data"
OUT.mkdir(exist_ok=True)


def wait(nvim, expression, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if nvim.exec_lua("return " + expression):
            return
        time.sleep(0.01)
    raise AssertionError("timeout: " + expression + "\n" + nvim.command_output("messages"))


def snapshot(nvim, name):
    wait(nvim, "s.closed or (not s.render_timer and not s.searching)")
    # screenstring queries the rendered, attached grid (including floating windows).
    lines = nvim.exec_lua("""
      vim.cmd('redraw')
      local lines = {}
      for row=1,vim.o.lines do
        local line={}
        for col=1,vim.o.columns do line[#line+1]=vim.fn.screenstring(row,col) end
        lines[#lines+1]=table.concat(line)
      end
      return lines
    """)
    (OUT / (name + ".txt")).write_text("\n".join(lines))
    return lines


def check_directory_alignment(nvim):
    nvim.exec_lua("""
      s.ui:render()
      local lines=vim.api.nvim_buf_get_lines(s.ui.bufs.list,0,-1,false)
      local directory='lua/xue-picker/'
      assert(lines[1]:sub(-#directory)==directory)
      local longest=0
      for _,line in ipairs(lines) do
        local left,path=line:match('^(.-)%s%s+([^%s]+/)$')
        if left then longest=math.max(longest,vim.fn.strdisplaywidth(left..'  '..path)) end
      end
      assert(longest>0)
      for _,line in ipairs(lines) do
        if line~='' then assert(vim.fn.strdisplaywidth(line)==longest) end
      end
    """)


def check_input_position(nvim, query, byte_col=None):
    byte_col = len(query.encode()) if byte_col is None else byte_col
    wait(nvim, "s.started and not s.render_timer and vim.fn.mode()=='i'")
    nvim.exec_lua(r"""
      local query,col=...
      assert(s.query==query, vim.inspect({expected=query,actual=s.query}))
      assert(vim.deep_equal(vim.api.nvim_buf_get_lines(s.input_buf,0,-1,false),{query}))
      assert(vim.api.nvim_get_current_win()==s.ui.wins.input)
      assert(vim.api.nvim_win_get_cursor(s.ui.wins.input)[2]==col)
      vim.cmd('redraw')
      local position=vim.api.nvim_win_get_position(s.ui.wins.input)
      local actual=position[2]+vim.fn.screencol()-1
      local expected=vim.fn.strdisplaywidth(s.opts.prompt..query:sub(1,col))
      assert(actual==expected, vim.inspect({expected=expected,actual=actual}))
    """, query, byte_col)


def check_input_editing(nvim):
    # Empty input and Home must leave the cursor after the protected prompt.
    for prompt in ("Grep> ", "🔎 café> "):
        nvim.exec_lua("s=require('xue-picker').pick({prompt=...,items={'alpha','beta'}})", prompt)
        check_input_position(nvim, "")
        nvim.input("alpha")
        wait(nvim, "s.query=='alpha'")
        check_input_position(nvim, "alpha")
        nvim.input("<Home><BS>")
        wait(nvim, "vim.api.nvim_win_get_cursor(s.ui.wins.input)[2]==0")
        check_input_position(nvim, "alpha", 0)
        nvim.input("X")
        wait(nvim, "s.query=='Xalpha'")
        check_input_position(nvim, "Xalpha", 1)
        nvim.input("<End><C-u>")
        wait(nvim, "s.query==''")
        check_input_position(nvim, "")
        nvim.api.paste("café\nnext", False, -1)
        wait(nvim, "s.query=='café next'")
        check_input_position(nvim, "café next")
        nvim.exec_lua("s:close(); s=require('xue-picker').resume()")
        check_input_position(nvim, "café next")
        nvim.exec_lua("s=require('xue-picker').pick({prompt=...,query='seed',items={}})", prompt)
        nvim.input("x")
        wait(nvim, "s.query=='seedx'")
        check_input_position(nvim, "seedx")
        nvim.exec_lua("s:close()")
    nvim.exec_lua("s=require('xue-picker.builtin').ui_input({prompt='Input> ',default='café'},function() end)")
    check_input_position(nvim, "café")
    nvim.input("!")
    wait(nvim, "s.query=='café!'")
    check_input_position(nvim, "café!")
    nvim.exec_lua("s:set_query(string.rep('x',200))")
    for width in (70, 32, 120):
        nvim.ui_try_resize(width, 40)
        wait(nvim, f"s.ui.width=={width} and not s.render_timer")
        nvim.exec_lua(r"""
          vim.cmd('redraw')
          local pos=vim.api.nvim_win_get_position(s.ui.wins.input)
          local col=pos[2]+vim.fn.screencol()-1
          assert(pos[2]==#s.opts.prompt and col>=pos[2] and col<s.ui.width)
          assert(vim.api.nvim_buf_get_lines(s.ui.bufs.prompt,0,1,false)[1]==s.opts.prompt)
        """)
        nvim.input("<Home>")
        wait(nvim, "vim.api.nvim_win_get_cursor(s.ui.wins.input)[2]==0")
        check_input_position(nvim, "x" * 200, 0)
        nvim.input("<End>")
        wait(nvim, "vim.api.nvim_win_get_cursor(s.ui.wins.input)[2]==200")
    nvim.exec_lua("s:set_query(''); s.opts.prompt=string.rep('📁/',50); s.ui:render()")
    nvim.ui_try_resize(32, 40)
    wait(nvim, "s.ui.width==32 and not s.render_timer")
    nvim.exec_lua(r"""
      local text=vim.api.nvim_buf_get_lines(s.ui.bufs.prompt,0,1,false)[1]
      local width=vim.fn.strdisplaywidth(text)
      assert(width<32 and vim.api.nvim_win_get_position(s.ui.wins.input)[2]==width)
      assert(vim.api.nvim_win_get_width(s.ui.wins.input)>0)
      assert(not vim.bo[s.ui.bufs.prompt].modifiable)
      assert(not vim.api.nvim_win_get_config(s.ui.wins.prompt).focusable)
    """)
    nvim.exec_lua("s.opts.prompt=''; s.ui:render()")
    check_input_position(nvim, "")
    nvim.exec_lua("s.opts.prompt='Grep> '; s.ui:render()")
    check_input_position(nvim, "")
    prompt_buf = nvim.exec_lua("return s.ui.bufs.prompt")
    nvim.exec_lua("s:close()")
    assert not nvim.api.buf_is_valid(prompt_buf)
    nvim.ui_try_resize(120, 40)


def run():
    faulthandler.dump_traceback_later(20, exit=True)
    nvim = pynvim.attach("child", argv=[os.environ.get("NVIM", "nvim"), "--embed", "-u", "NONE", "-i", "NONE", "--noplugin"])
    try:
        nvim.ui_attach(120, 40, rgb=True)
        nvim.exec_lua("vim.opt.rtp:prepend(...)", str(ROOT))
        nvim.command("runtime plugin/xue-picker.lua")
        nvim.exec_lua("vim.o.cmdheight=0; vim.o.swapfile=false; vim.g.xue_origin=vim.api.nvim_get_current_win()")
        check_input_editing(nvim)
        nvim.exec_lua("s=require('xue-picker.builtin').files({cwd=..., git={enabled=false}})", str(ROOT))
        wait(nvim, "s.closed or (not s.loading and not s.searching)")
        assert not nvim.exec_lua("return s.closed"), nvim.command_output("messages")
        assert nvim.exec_lua("return #s.results") > 10
        nvim.input("matcher")
        wait(nvim, "s.query=='matcher' and not s.searching and #s.results>0")
        assert nvim.exec_lua("return s.results[1].text") == "lua/xue-picker/matcher.lua"
        check_directory_alignment(nvim)
        snapshot(nvim, "ui-files")
        nvim.input("<C-o>")
        wait(nvim, "s.ui.wins.preview ~= nil")
        wait(nvim, "vim.api.nvim_buf_get_lines(s.ui.bufs.preview,0,1,false)[1]:find('Independent',1,true) ~= nil")
        check_directory_alignment(nvim)
        snapshot(nvim, "ui-preview-wide")
        nvim.exec_lua("vim.api.nvim_echo({{'XUE_MESSAGE_VISIBLE','Normal'}},false,{})")
        lines = snapshot(nvim, "ui-message")
        assert any("XUE_MESSAGE_VISIBLE" in line for line in lines)
        nvim.ui_try_resize(70, 40)
        wait(nvim, "s.ui.width == 70")
        assert nvim.exec_lua("return s.ui.wins.preview ~= nil")
        check_directory_alignment(nvim)
        snapshot(nvim, "ui-preview-narrow")
        nvim.ui_try_resize(32, 12)
        wait(nvim, "s.ui.width == 32")
        assert nvim.exec_lua("return s.ui.wins.preview == nil")
        check_directory_alignment(nvim)
        snapshot(nvim, "ui-tiny")
        nvim.input("<Esc>")
        wait(nvim, "s.closed")
        assert nvim.exec_lua("return vim.o.cmdheight == 0 and vim.api.nvim_get_current_win()==vim.g.xue_origin")
        nvim.ui_try_resize(120, 40)
        nvim.exec_lua("s=require('xue-picker').resume()")
        wait(nvim, "not s.loading and not s.searching")
        assert nvim.exec_lua("return s.query=='matcher' and s.preview_enabled")
        nvim.exec_lua("s:close(); vim.o.cmdheight=1")
        nvim.exec_lua("s=require('xue-picker').pick({items={'one','two','three'},hint=false,keymaps={next={'<C-j>','<Down>'}}})")
        wait(nvim, "not s.searching and #s.results==3")
        assert nvim.exec_lua("return s.ui.wins.hint==nil and vim.api.nvim_win_get_height(s.ui.wins.list)==s.ui.height-1")
        nvim.input("<C-j>")
        wait(nvim, "s.index==2")
        nvim.input("<Down>")
        wait(nvim, "s.index==3")
        nvim.command("colorscheme default")
        snapshot(nvim, "ui-keymaps-theme")
        nvim.exec_lua("s:close()")
        assert nvim.exec_lua("return vim.o.cmdheight==1")
        assert not nvim.exec_lua("return vim.api.nvim_buf_is_valid(s.input_buf)")
        nvim.exec_lua("s=require('xue-picker.builtin').live_grep({cwd=...,backend='ripgrep',query='function',git={enabled=false},icons=function() return '◆ ', 'Special' end})", str(ROOT))
        wait(nvim, "not s.loading and not s.searching and #s.results>0")
        nvim.exec_lua("""
          s.ui:render()
          local lines=vim.api.nvim_buf_get_lines(s.ui.bufs.list,0,2,false)
          assert(lines[1]=='  ◆ '..require('xue-picker.util').relative(s.results[1].path,s.opts.cwd))
          assert(lines[2]:match('^▸%s+%d+:%s*%d+  '))
          assert(not lines[2]:find('◆',1,true))
        """)
        for _ in range(22):
            nvim.input("<C-n>")
        wait(nvim, "s.index==23")
        snapshot(nvim, "ui-grep-scroll")
        nvim.input("<C-x><C-n><C-x><CR>")
        wait(nvim, "s.closed")
        assert len(nvim.funcs.getqflist()) == 2
        nvim.command("cclose")
        nvim.exec_lua(r"""
          local root=...
          diagnostic_ns=vim.api.nvim_create_namespace('xue-ui-diagnostics')
          diagnostic_buf=vim.api.nvim_create_buf(false,true)
          vim.api.nvim_buf_set_name(diagnostic_buf, root..'/.test-data/ui-diagnostics.lua')
          local lines,diagnostics={},{}
          for i=1,16 do
            lines[i]='local value'..i..' = '..i
            diagnostics[i]={lnum=i-1,col=6,severity=(i-1)%4+1,source='lua_ls',code='D'..i,
              message='Diagnostic café '..i..' with a longer explanation to exercise wrapping.\nExpected a different value.'}
          end
          vim.api.nvim_buf_set_lines(diagnostic_buf,0,-1,false,lines)
          vim.diagnostic.set(diagnostic_ns,diagnostic_buf,diagnostics)
          s=require('xue-picker.builtin').diagnostics({cwd=root,bufnr=diagnostic_buf,sort='reverse'})
        """, str(ROOT))
        wait(nvim, "s.started and not s.loading and not s.searching")
        lines = snapshot(nvim, "ui-diagnostics")
        assert any("[lua_ls]" in line for line in lines)
        assert any("Diagnostic café" in line for line in lines)
        for _ in range(7):
            nvim.input("<C-n>")
        wait(nvim, "s.index==8")
        for width in (70, 32, 120):
            nvim.ui_try_resize(width, 40)
            wait(nvim, f"s.ui.width=={width}")
            lines = snapshot(nvim, f"ui-diagnostics-{width}")
            nvim.exec_lua(r"""
              local lines=vim.api.nvim_buf_get_lines(s.ui.bufs.list,0,-1,false)
              for _,line in ipairs(lines) do assert(vim.fn.strdisplaywidth(line)<=s.ui.list_width) end
              assert(table.concat(lines,'\n'):find('['..s.results[s.index].code..']',1,true))
              local selected=false
              for _,mark in ipairs(vim.api.nvim_buf_get_extmarks(s.ui.bufs.list,-1,0,-1,{details=true})) do
                if mark[4].line_hl_group=='XuePickerSelected' then selected=true end
              end
              assert(selected)
            """)
        nvim.exec_lua("diagnostic_target=s.results[s.index]")
        nvim.input("<CR>")
        wait(nvim, "s.closed")
        assert nvim.exec_lua("return vim.api.nvim_get_current_buf()==diagnostic_buf and vim.api.nvim_win_get_cursor(0)[1]==diagnostic_target.lnum")
        nvim.exec_lua("vim.diagnostic.reset(diagnostic_ns); vim.api.nvim_buf_delete(diagnostic_buf,{force=true})")
        nvim.exec_lua("s=require('xue-picker.builtin').files({cwd=...})", str(ROOT))
        wait(nvim, "s.started")
        nvim.command("tabnew")
        wait(nvim, "s.closed")
        assert nvim.exec_lua("return vim.o.cmdheight==1")
        nvim.command("tabclose")
        nvim.exec_lua("calls={}; s=require('xue-picker.builtin').ui_input({default='hello',completion='file'},function(v) calls[#calls+1]={v} end)")
        wait(nvim, "s.started")
        nvim.input("<CR>")
        wait(nvim, "s.closed")
        assert nvim.exec_lua("return #calls==1 and calls[1][1]=='hello'")
        nvim.exec_lua("s=require('xue-picker.builtin').ui_select({'same','same'},{},function(v,i) calls[#calls+1]={v,i} end)")
        wait(nvim, "#s.results==2 and not s.searching")
        nvim.input("<C-n><CR>")
        wait(nvim, "s.closed")
        assert nvim.exec_lua("return #calls==2 and calls[2][2]==2")
        nvim.exec_lua("s=require('xue-picker.builtin').files({cwd=...})", str(ROOT))
        wait(nvim, "s.started")
        nvim.exec_lua("t=require('xue-picker.builtin').buffers()")
        assert nvim.exec_lua("return s.closed and not t.closed")
        nvim.exec_lua("t:close()")
        nvim.exec_lua("s=require('xue-picker').pick({items={'one'}})")
        wait(nvim, "s.started")
        nvim.input("<C-\\><C-n>:")
        wait(nvim, "s.closed")
        nvim.input("<Esc>")
        nvim.exec_lua("history_text='let g:xue_executed=1\\nlet g:xue_executed=2'; vim.fn.histadd('cmd',history_text); s=require('xue-picker.builtin').history()")
        wait(nvim, "s.started and not s.loading and not s.searching")
        nvim.input("<CR>")
        wait(nvim, "vim.fn.getcmdtype()==':' and vim.fn.getcmdline()==history_text")
        assert nvim.exec_lua("return vim.g.xue_executed==nil")
        nvim.input("<Esc>")
        messages = nvim.command_output("messages")
        assert "Error" not in messages and "E5108" not in messages, messages
        print("Attached UI: files, input, mappings, preview, resize, grep groups, diagnostics, scroll, quickfix, resume, tabs, callbacks OK")
    finally:
        try:
            nvim.command("qa!")
        except (EOFError, OSError):
            pass
        nvim.close()
        faulthandler.cancel_dump_traceback_later()


if __name__ == "__main__":
    run()
