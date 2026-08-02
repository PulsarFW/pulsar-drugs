fx_version 'cerulean'
games({ 'gta5' })

name 'Pulsar Drugs'
description 'Drug production: coke, meth, and moonshine'
author 'Artmines - maintained for Pulsar Framework'
url 'https://pulsarframe.work'
version 'v1.0.0'

version_check 'yes'
github 'https://github.com/PulsarFW/pulsar_drugs'

client_script '@pulsar_core/components/cl_error.lua'
shared_script '@pulsar_core/core/sh_pulsar.lua'
client_script '@pulsar_pwnzor/client/check.lua'
server_script '@oxmysql/lib/MySQL.lua'

shared_scripts({
	'shared/**/*.lua',
})

client_scripts({
	'@pulsar_damage/data/weapons.lua',
	'client/**/*.lua',
})

server_scripts({
	'server/**/*.lua',
})

lua54 'yes'