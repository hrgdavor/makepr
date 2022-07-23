#!/usr/bin/env node

import { default as fs} from 'fs'
import { default as chalk } from 'chalk'
import {findUpSync} from 'find-up'
import { exec } from 'child_process'

const argv = process.argv.slice(2)

if(argv.length && argv[0] === '--help'){
		printHelp()
}

doInfo(argv)

function printHelp(){
console.log(chalk`
`);	
}

function doInfo(argv){
	const settings = getSettings('./')
	if(!settings.url){
		console.log(settings.packageJson ? 'makepr.url not defined in package.json' : 'package.json not found')
		process.exit(1)
	}else{
		exec('git branch --show-current', (err, stdout, stderr) => {
			if (err) {
					console.log('ERROR '+err);
			}else{
					const branch = stdout.trim()
					const url = settings.url.replace('{BRANCH}',branch)
					console.log(url);
					var start = (process.platform == 'darwin'? 'open': process.platform == 'win32'? 'start': 'xdg-open');
					exec(start + ' ' + url)
			}
		})		
	}
}

function getSettings(cwd){
	let pjsonFile = findUpSync('package.json',{cwd}) 
	let config = {}
	if(pjsonFile){
		let data = fs.readFileSync(pjsonFile)
		data = data.toString('utf-8')
		
		// Remove a possible UTF-8 BOM (byte order marker) as this can lead to parse values when passed in to the JSON.parse.
	  if (data.charCodeAt(0) === 0xFEFF) data = data.slice(1);		

		try { 
			config = JSON.parse(data)
		}catch (e) { }
	}

	return {
		...(config || {}).makepr,
		packageJson: config ? true : false
	}
}