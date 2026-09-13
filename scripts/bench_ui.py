"""Attached-UI first paint and real disk benchmark. Requires pynvim."""
import json
import os
import pathlib
import tempfile
import time

import pynvim

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run():
    result = {"ui": [], "grep": []}
    nvim = pynvim.attach("child", argv=[os.environ.get("NVIM", "nvim"), "--embed", "-u", "NONE", "-i", "NONE", "--noplugin"])
    try:
        nvim.ui_attach(120, 40, rgb=True)
        nvim.exec_lua("vim.opt.rtp:prepend(...)", str(ROOT))
        for count in (20000, 100000):
            result["ui"].append(nvim.exec_lua("""
              local count=...
              local U=require('xue-picker.util')
              local items={}
              for i=1,count do
                items[i]=U.file(('pkg%03d/file%06d.lua'):format(i%200,i),'/repo')
              end
              local function now() return vim.uv.hrtime()/1e6 end
              local start=now()
              local s=require('xue-picker').pick({items=items,cwd='/repo',git={enabled=false}})
              local input=now()-start
              assert(vim.wait(30000,function() return s.started and not s.loading and not s.searching and not s.render_timer end,1))
              local cold=now()-start
              s:close()
              start=now()
              s=require('xue-picker').resume()
              local warm_input=now()-start
              local first=now()-start
              assert(vim.wait(30000,function() return s.started and not s.loading and not s.searching and not s.render_timer end,1))
              local warm=now()-start
              s:close()
              return {candidates=count,input_ms=input,cold_results_ms=cold,warm_input_ms=warm_input,warm_first_results_ms=first,warm_refresh_ms=warm}
            """, count))
        with tempfile.TemporaryDirectory(prefix="xue-disk-") as directory:
            base = pathlib.Path(directory)
            start = time.monotonic()
            for i in range(20000):
                folder = base / f"pkg{i % 100:03}"
                folder.mkdir(exist_ok=True)
                (folder / f"file{i:06}.txt").write_text(f"unique{i:06}\nhi🌍 needle {i}\n")
            result["fixture_creation_ms"] = (time.monotonic() - start) * 1000
            result["disk"] = nvim.exec_lua("""
              local cwd=...
              local function now() return vim.uv.hrtime()/1e6 end
              local start=now()
              local s=require('xue-picker.builtin').files({cwd=cwd,git={enabled=false}})
              local input=now()-start
              assert(vim.wait(30000,function() return s.started and not s.loading and not s.searching end,1))
              local cold=now()-start
              s:close()
              start=now()
              s=require('xue-picker.builtin').files({cwd=cwd,git={enabled=false}})
              assert(vim.wait(30000,function() return s.first_results_at ~= nil end,1))
              local cache=s.first_results_at-start
              assert(vim.wait(30000,function() return not s.loading and not s.searching end,1))
              local refreshed=now()-start
              s:close()
              return {files=20000,input_ms=input,scan_and_rank_ms=cold,cache_first_results_ms=cache,refresh_ms=refreshed}
            """, directory)
            for backend in ("ripgrep", "auto"):
                for query in ("needle", "absent-24122"):
                    result["grep"].append(nvim.exec_lua("""
                      local args=...
                      local start=vim.uv.hrtime()
                      local s=require('xue-picker.builtin').live_grep({cwd=args[1],backend=args[2],query=args[3],git={enabled=false}})
                      assert(vim.wait(30000,function() return s.started and not s.loading and not s.searching end,1))
                      local result={requested=args[2],backend=s.backend,query=args[3],ms=(vim.uv.hrtime()-start)/1e6,count=#s.results,fallback=s.fallback}
                      s:close()
                      start=vim.uv.hrtime()
                      s=require('xue-picker.builtin').live_grep({cwd=args[1],backend=args[2],query='needle',git={enabled=false}})
                      s:close()
                      result.cancel_ms=(vim.uv.hrtime()-start)/1e6
                      return result
                    """, [directory, backend, query]))
        root = ROOT / ".test-data"
        root.mkdir(exist_ok=True)
        (root / "ui-perf.json").write_text(json.dumps(result, indent=2, ensure_ascii=False))
        print(json.dumps(result, indent=2, ensure_ascii=False))
    finally:
        try:
            nvim.command("qa!")
        except (EOFError, OSError):
            pass
        nvim.close()


if __name__ == "__main__":
    run()
