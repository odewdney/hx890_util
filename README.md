# HX890 Powershell programming tool


With information from 
- https://pc5e.nl/info/standard-horizon-hx890e-marine-handheld
- https://johannessen.github.io/hx870/

Save the eeprom data using the YCE20 or hxtool, edit using the powershell function below, and then upload back to the radio.

The scripts take a "-fn" paramater for the filename, which defaults to ***test.dat***

## FM Radio
Get-Hx890FM \[-slot N]

Set-Hx890FM -slot N -enable|-disable -name <name> -freq <frequance>

## CG
Channel Group

Get-Hx890CG

## Channels
Get-Hx890CH \[-group N] \[-slot N]

Set-Hx890CH \[-group N] -slot N

## Extra Channels
For access to RG, EXP and WX channels settings

Get-Hx890RG \[-rg|-exp|-wx] \[-slot N]

Set-Hx890RG \[-rg|-exp|-wx] -slot N -channel "XX" -name name -enable|-disable -intl|-us|-region -rx_freq <freq> -tx_freq <freq> -tx \[rx|tx|1w|1wonly]



