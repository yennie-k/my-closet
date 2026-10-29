// Foreground child kept in the tool's local process session; no deployment command exists here.
import { spawn } from 'node:child_process';
import { join } from 'node:path';
import { LOCAL,guard } from './integration.mjs';
guard();
const cli=join(LOCAL,'node_modules/@supabase/cli-windows-x64/bin/supabase.exe');
const child=spawn(cli,['functions','serve','verify-garment-photo'],{cwd:LOCAL,windowsHide:true,stdio:'inherit'});
child.on('close',code=>process.exitCode=code||0);
process.on('SIGINT',()=>child.kill('SIGINT'));
