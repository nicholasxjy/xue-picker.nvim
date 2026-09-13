"""Optional cell-level comparison with fzf-lua's real buffers picker."""
import os
import pathlib
import tempfile
import time

import pynvim


def check_reference(path):
    root = pathlib.Path(__file__).resolve().parents[1]
    colors = {}
    with tempfile.TemporaryDirectory(prefix="xue-buffers-") as directory:
        directory = str(pathlib.Path(directory).resolve())
        mock = pathlib.Path(directory) / "lua" / "nvim-web-devicons.lua"
        mock.parent.mkdir()
        mock.write_text("""
          local icon={icon='λ',color='#b060ff',name='Fixture'}
          local default={icon='',color='#6d8086',name='Default'}
          return {
            setup=function()end,refresh=function()end,has_loaded=function()return true end,
            get_icons=function()return {[1]=default,lua=icon,txt=icon} end,
            get_icons_by_filename=function()return {} end,
            get_icons_by_extension=function()return {lua=icon,txt=icon} end,
            get_icon=function(name)
              if name:match('%.lua$') or name:match('%.txt$') then return 'λ','XueFixtureIcon' end
              return '','XueFixtureDefault'
            end,
          }
        """)
        nvim = pynvim.attach("child", argv=[os.environ.get("NVIM", "nvim"), "--embed", "-u", "NONE", "-i", "NONE", "--noplugin"])

        def wait(expression):
            deadline = time.monotonic() + 8
            while time.monotonic() < deadline:
                if nvim.exec_lua("return " + expression):
                    return
                time.sleep(0.01)
            raise AssertionError(expression + "\n" + nvim.command_output("messages"))

        def rows():
            data = nvim.exec_lua("""
              vim.cmd('redraw')
              local out={}
              for row=1,vim.o.lines do
                local text,cells='',{}
                for col=1,vim.o.columns do
                  local char=vim.fn.screenstring(row,col)
                  text=text..char
                  cells[#cells+1]={char,vim.fn.screenattr(row,col)}
                end
                local id=tonumber(text:match('%[(%d+)%]'))
                if not id and text:find('other',1,true) then id=ids[2] end
                if id and vim.tbl_contains(ids,id) then out[tostring(id)]=cells end
              end
              return out
            """)
            while nvim._session._pending_messages:
                message = nvim.next_message()
                if message.name == "redraw":
                    for event in message.args:
                        if event[0] == "hl_attr_define":
                            for definition in event[1:]:
                                colors[definition[0]] = definition[1]
            return {buf: [[char, colors[attr] if attr else {}] for char, attr in cells] for buf, cells in data.items()}

        def compare(expected, case):
            actual = rows()
            assert actual.keys() == expected.keys(), (case, actual.keys(), expected.keys())
            for buf in expected:
                differences = [(i + 1, a, b) for i, (a, b) in enumerate(zip(actual[buf], expected[buf])) if a != b]
                assert not differences, (case, buf, differences[:6] + differences[-2:])
            output = root / ".test-data" / ("ui-buffers-" + case + ".txt")
            screen = nvim.exec_lua("""
              local lines={}
              for row=1,vim.o.lines do
                local line=''
                for col=1,vim.o.columns do line=line..vim.fn.screenstring(row,col) end
                lines[#lines+1]=line
              end
              return lines
            """)
            output.write_text("\n".join(screen))

        try:
            nvim.ui_attach(120, 40, rgb=True, ext_linegrid=True)
            nvim.exec_lua("""
              local root,reference,cwd=...
              vim.opt.rtp:prepend(root);vim.opt.rtp:append(reference);vim.opt.rtp:append(cwd)
              vim.env.NO_COLOR=nil;vim.o.termguicolors=true;vim.o.hidden=true;vim.o.swapfile=false
              vim.api.nvim_set_current_dir(cwd)
              require('nvim-web-devicons')
              vim.api.nvim_set_hl(0,'XueFixtureIcon',{fg='#b060ff'})
              vim.api.nvim_set_hl(0,'XueFixtureDefault',{fg='#6d8086'})
              ids={vim.api.nvim_get_current_buf()}
              vim.api.nvim_buf_set_name(ids[1],cwd..'/src/café🌟.lua')
              vim.api.nvim_buf_set_lines(ids[1],0,-1,false,{'one','two'});vim.bo.modified=false
              vim.api.nvim_win_set_cursor(0,{2,0})
              for _=1,12 do local b=vim.api.nvim_create_buf(false,true);vim.api.nvim_buf_delete(b,{force=true}) end
              ids[2]=vim.api.nvim_create_buf(true,false)
              vim.api.nvim_buf_set_name(ids[2],cwd..'/nested/readonly-other.txt')
              vim.api.nvim_set_current_buf(ids[2])
              vim.api.nvim_buf_set_lines(ids[2],0,-1,false,{'one','two','three'})
              vim.api.nvim_win_set_cursor(0,{3,1});vim.bo.readonly=true
              ids[3]=vim.api.nvim_create_buf(true,false)
              vim.fn.writefile({'one'},cwd..'/unloaded.lua')
              ids[4]=vim.fn.bufadd(cwd..'/unloaded.lua');vim.bo[ids[4]].buflisted=true
              ids[5]=vim.api.nvim_create_buf(true,false);vim.api.nvim_buf_set_name(ids[5],'xue://example/resource')
              ids[6]=vim.api.nvim_create_buf(true,false);vim.api.nvim_buf_set_name(ids[6],'term://fixture')
              vim.api.nvim_open_term(ids[6],{});vim.b[ids[6]].term_title='fixture-terminal'
              vim.api.nvim_set_current_buf(ids[3]);vim.api.nvim_set_current_buf(ids[1])
            """, str(root), path, directory)
            for background in ("dark", "light"):
                nvim.exec_lua("""
                  vim.o.background=...
                  require('fzf-lua').setup({winopts={height=.7,width=1,row=1,col=0,border='none',preview={hidden=true}},fzf_colors=true})
                  require('fzf-lua').setup_highlights(true)
                  if vim.o.background=='light' then
                    vim.api.nvim_set_hl(0,'FzfLuaFzfHeader',{fg='#7d398f'})
                  end
                """, background)
                for mode in ("relative", "icons", "filename_first", "filename_only"):
                    for width in (120, 60, 32):
                        nvim.ui_try_resize(width, 40)
                        nvim.exec_lua("""
                          local mode=...
                          vim.api.nvim_set_current_buf(ids[3]);vim.api.nvim_set_current_buf(ids[1])
                          require('fzf-lua').buffers({file_icons=mode=='icons',previewer=false,buffers=ids,
                            filename_only=mode=='filename_only',formatter=mode=='filename_first' and 'path.filename_first' or false})
                        """, mode)
                        wait("""(function()
                          if vim.bo.filetype~='fzf' or vim.fn.mode()~='t' then return false end
                          local seen={}
                          for _,line in ipairs(vim.api.nvim_buf_get_lines(0,0,-1,false)) do
                            local id=tonumber(line:match('%[(%d+)%]'))
                            if id and vim.tbl_contains(ids,id) then seen[id]=true end
                          end
                          return vim.tbl_count(seen)==#ids
                        end)()""")
                        expected = rows()
                        nvim.input("other")
                        wait("table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),' '):find('1/5',1,true)~=nil")
                        nvim.input("<Tab>")
                        wait("table.concat(vim.api.nvim_buf_get_lines(0,0,-1,false),' '):find('1/5 (1)',1,true)~=nil")
                        filtered = rows()
                        nvim.input("<Esc>")
                        wait("vim.bo.filetype~='fzf'")
                        nvim.exec_lua("""
                          local mode=...
                          vim.api.nvim_set_current_buf(ids[3]);vim.api.nvim_set_current_buf(ids[1])
                          s=require('xue-picker.builtin').buffers({icons=mode=='icons' and 'auto' or false,
                            path_format=mode=='filename_first' and 'filename_first' or 'relative',filename_only=mode=='filename_only',
                            filter={fn=function(item)return vim.tbl_contains(ids,item.bufnr) end}})
                        """, mode)
                        wait("s.started and not s.loading and not s.searching and not s.render_timer")
                        compare(expected, f"{background}-{mode}-{width}")
                        nvim.exec_lua("s:set_query('other')")
                        wait("#s.results==1 and not s.searching and not s.render_timer")
                        nvim.exec_lua("s:act('toggle');s.ui:render()")
                        compare(filtered, f"{background}-{mode}-{width}-filtered")
                        nvim.exec_lua("s:close()")
            print("Attached fzf-lua buffers: text/RGB parity for numbers, flags, pinned current buffer, selection, icons, paths and line numbers in dark/light at 120/60/32 columns")
        finally:
            try:
                nvim.command("qa!")
            except (EOFError, OSError):
                pass
            nvim.close()


if __name__ == "__main__":
    check_reference(os.environ["XUE_FZF_LUA"])
