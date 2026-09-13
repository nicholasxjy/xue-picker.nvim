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
      local line=vim.api.nvim_buf_get_lines(s.ui.bufs.list,0,1,false)[1]
      local directory='lua/xue-picker/'
      assert(line:sub(-#directory)==directory)
      assert(vim.fn.strdisplaywidth(line)==vim.api.nvim_win_get_width(s.ui.wins.list))
    """)


def run():
    faulthandler.dump_traceback_later(20, exit=True)
    nvim = pynvim.attach("child", argv=[os.environ.get("NVIM", "nvim"), "--embed", "-u", "NONE", "-i", "NONE", "--noplugin"])
    try:
        nvim.ui_attach(120, 40, rgb=True)
        nvim.exec_lua("vim.opt.rtp:prepend(...)", str(ROOT))
        nvim.command("runtime plugin/xue-picker.lua")
        nvim.exec_lua("vim.o.cmdheight=0; vim.o.swapfile=false; vim.g.xue_origin=vim.api.nvim_get_current_win()")
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
        print("Attached UI: files, input, mappings, preview, resize, grep groups, scroll, quickfix, resume, tabs, callbacks OK")
    finally:
        try:
            nvim.command("qa!")
        except (EOFError, OSError):
            pass
        nvim.close()
        faulthandler.cancel_dump_traceback_later()


if __name__ == "__main__":
    run()
