"""Execute the real updater with fixture home paths and inert unrelated tools."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE=Path(__file__).resolve().parents[1]/'homebrew-update.1h.sh'

class FleetGuardStatus(unittest.TestCase):
    def run_updater(self,status):
        with tempfile.TemporaryDirectory(prefix='swiftbar-owner-') as work:
            root=Path(work)
            script=root/'homebrew-update.1h.sh'
            # Relocate paths only; execute the complete updater's real control flow.
            script.write_text(SOURCE.read_text().replace('$HOME',str(root)))
            policy=root/'.config/fleet-maintenance/npm-guard.json';policy.parent.mkdir(parents=True);policy.write_text('{}')
            guard=root/'.local/share/fleet-maintenance/guards/npm';guard.parent.mkdir(parents=True)
            guard.write_text('#!/bin/bash\nexit '+str(status)+'\n');guard.chmod(0o700)
            shim=root/'unrelated-tools.sh'
            shim.write_text('''function /opt/homebrew/bin/brew { :; }
function /usr/local/bin/brew { :; }
function /opt/homebrew/bin/mas { :; }
function /usr/local/bin/mas { :; }
function mas { :; }
function pgrep { return 1; }
function osascript { :; }
function defaults {
 if [[ "$1" == write ]]; then printf 'written' > "$FM_TEST_TIMESTAMP"; else printf '0\\n'; fi
}
function npm { printf 'unexpected npm fallback' >&2; return 99; }
''')
            marker=root/'timestamp';env=dict(os.environ,BASH_ENV=str(shim),FM_TEST_TIMESTAMP=str(marker))
            for key in ('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy'):env[key]='http://127.0.0.1:1'
            env['NO_PROXY']=env['no_proxy']='127.0.0.1,localhost'
            result=subprocess.run(['/bin/bash',str(script),'run_update'],env=env,capture_output=True,text=True,timeout=10)
            return result,marker.exists()

    def test_guard_failure_keeps_weekly_update_due(self):
        result,stamped=self.run_updater(7)
        self.assertEqual(result.returncode,7,result.stdout+result.stderr)
        self.assertFalse(stamped)

    def test_guard_success_can_record_weekly_completion(self):
        result,stamped=self.run_updater(0)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertTrue(stamped)

if __name__=='__main__':unittest.main()
