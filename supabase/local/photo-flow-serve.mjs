// Serve the original verifier and new operations endpoint locally. No deployment.
import {spawn} from 'node:child_process';
import {join} from 'node:path';
import {LOCAL,guard} from './integration.mjs';
guard();
const child=spawn(join(LOCAL,'node_modules/@supabase/cli-windows-x64/bin/supabase.exe'),['functions','serve'],{cwd:LOCAL,windowsHide:true,stdio:'inherit'});
child.on('close',code=>process.exitCode=code||0);
process.on('SIGINT',()=>child.kill('SIGINT'));
