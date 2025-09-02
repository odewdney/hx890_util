
$HX890_FILENAME = "test.dat"

function loadBin
{
    [OutputType([byte[]])]
    param([string]$fn)
    return [System.IO.File]::ReadAllBytes($fn)
}

function saveBin([string]$fn, [byte[]]$d){
    [System.IO.File]::WriteAllBytes($fn, $d)
}

function iif($b, $t, $f){ if($b) {$t} else {$f}}

function readString([byte[]]$d, [int]$o, [int]$l=16){
    $ret = ""
    for($n=0; $n -lt $l;$n=$n+1){
        [char]$c = $d[$o+$n]
        if ($c -eq 0xff ) { break }
        $ret = $ret + $c
    }
    return $ret
}

function writeString([ref][byte[]]$dd, [int]$o, [string]$s, [int]$l){
    $d = $dd.value
    for($n=0; $n -lt $l; $n=$n+1){
        [byte]$c = 0xff
        if ( $n -lt $s.Length ){
            $c = [byte]($s[$n])
        }
        $d[$o+$n] = $c
    }
}

function Get-hx890Fm
{
 param( [string] $fn = $HX890_FILENAME, [nullable[int]] $slot)

    $d = loadBin $fn

    function DumpSlot([byte[]]$d, [int]$o){
        $ret = @{}
        if ($d[$o] -ne 1){ $ret.state = "unassigned" }
        else {
            $ret.state = "ok"
            $ret.freq = "$($d[$o+1] -shr 4 )$($d[$o+1] % 16)$($d[$o+2] -shr 4 ).$($d[$o+2] % 16)$($d[$o+3] -shr 4 )$($d[$o+3] % 16)" 
            $ret.name = readString $d ($o+4) 12
        }

        return new-object psobject -Property $ret
    }

    if (!$slot)
    {
        for($n = 0; $n -lt 20; $n=$n+1){
            DumpSlot $d (0x500 + 0x10 * $n)
        }
    } else {
            DumpSlot $d (0x500 + 0x10 * $slot)
    }
}

function getBCD($f){
    return [int](([math]::floor($f/10) % 10) * 16 + ([math]::Floor($f) % 10))
}

function fromBCD([byte]$b){
    return (($b -shr 4) * 10) + ($b -band 15)
}

function Set-Hx890Fm {
    param([string]$fn = $HX890_FILENAME,
        [parameter(mandatory=$true)] [int]$slot,
        [switch]$enable,
        [switch]$disable,
        [string]$name,
        [nullable[float]]$freq
        )
    $d = loadBin $fn
    $o = 0x500 + 0x10 * $slot
    
    if($enable){
        $d[$o] = 1
    }
    if($disable){
        $d[$o] = 0xff
    }

    if ($name) {
        writeString ([ref]$d) ($o + 4) $name 12
        #readString $d ($o + 4) 12
    }

    if($freq){
        [float]$f = $freq + 0.0001
        $d[$o+1] = getBCD($f / 10)
        $d[$o+2] = getBCD($f * 10)
        $d[$o+3] = getBCD($f * 1000)
        #"set freq $f"
    }

    saveBin $fn $d
}

function Get-Hx890CG{
    param([string]$fn = $HX890_FILENAME,
        [nullable[int]] $slot
    )

    $d = loadBin $fn

    function DumpSlot($d, $s){
        $ret = @{}
        $o = 0x70 + $s * 0x10

        $ret.slot = $s
        if ($d[$o] -eq 0){
            $ret.state = "Disabled"
        } else {
            $ret.state = "Enabled"
            $ret.DSC = !!$d[$o+1]
            $ret.AITS = !!$d[$o+2]
            $ret.name = readString $d ($o+3) 4
            $ret.model = readstring $d ($o+8) 6
        }

        return New-Object psobject -Property $ret
    }

    if($slot -ne $null) {
        DumpSlot $d, $slot
    } else {
        for($n=0; $n -lt 4; $n=$n+1){
            DumpSlot $d $n
        }
    }
}



function Get-Hx890CH{
    param([string]$fn = $HX890_FILENAME,
        [int]$group = 2,
        [nullable[int]] $slot
    )

    $d = loadBin $fn

    [string[]]$defProp = @("Channel", "Suffix", "Prefix","FreqShiftRX","FreqShiftTX","TX","HP","HPTx","ship2ship","cg","defaultName","customName")
    $defPropSet = New-Object System.Management.Automation.PSPropertySet("DefaultDisplayPropertySet", $defProp)
    [System.Management.Automation.PSMemberInfo[]]$stdMem = @($defPropSet)


    function DumpSlot($d, $g, $s){
        $ret = @{}

        $ret.Group = $g
        $ret.Slot = $s

        $o = 0x700 + $g * 0x200 + $s * 4
        
        $ret.channel = $d[$o]
        $b1 = $d[$o+1]
        $ret.FreqShiftRx = !!($b1 -band 128)
        $ret.FreqShiftTx = !!($b1 -band 64)
        $ret.HP = !!($b1 -band 32)
        $ret.Tx = !!($b1 -band 16)
        $ret.HPTx = !!($b1 -band 8)
        $ret.suffix = switch( $b1 -band 3 ) {
            0 { "" }
            1 { "A" }
            2 { "B" }
            3 { "Unk" }
            }
        $b2 = $d[$o+2]
        $ret.ship2ship = !!($b2 -band 128 )
        $ret.prefix = if (($b2 -band 127) -eq 0x7f) { "" } else { ($b2 -band 127 ).ToString() }
        $b3 = $d[$o+3]
        if ($b3 -band 128){
            $ret.scrambled = $true
        }

        $oo = 0x120 + 0x20 * $g + [int][math]::Floor($s / 8)
        $ob = 128 -shr ($s % 8)
        $ret.cg = !!($d[$oo] -band $ob)

        $ret.defaultName = readstring $d (0x1100 + $g * 0xc00 + $s * 0x10) 16

        $ret.customName = readstring $d (0x1700 + $g * 0xc00 + $s * 0x10) 16
 
        return New-Object psobject -Property $ret
    }

    if($slot -ne $null) {
        $r = DumpSlot $d $group $slot
            $r | Add-Member MemberSet PSStandardMembers $stdMem
            $r
    } else {
        for($n=0; $n -lt (0xb * 8); $n=$n+1){
            $r = DumpSlot $d $group $n
            $r | Add-Member MemberSet PSStandardMembers $stdMem
            $r
        }
    }
}


function Get-Hx890RG{
    param([string]$fn = $HX890_FILENAME,
        [switch]$rg,
        [switch]$exp,
        [switch]$wx,
        [nullable[int]] $slot
    )

    $d = loadBin $fn

    [string[]]$defProp = @("Channel", "rx_freq", "tx_freq","US","INTL","RG","TX","tx_pwr","cg","customName")
    $defPropSet = New-Object System.Management.Automation.PSPropertySet("DefaultDisplayPropertySet", $defProp)
    [System.Management.Automation.PSMemberInfo[]]$stdMem = @($defPropSet)

    # g=0 for RG 1 ffor EXP
    function DumpSlot($d, $g, $s){
        $ret = @{}

        $ret.Group = switch ($g){ 0 {"RG"} 1 { "EXP" } 2 { "WX" } default {"unknown"}}
        $ret.Slot = $s

        if ($g -ne 2){
        $o = 0xd00 + $g * 0x200 + $s * 0x10
        
        $b0 = $d[$o+0]
        $ret.US = !!($b0 -band 0x80)
        $ret.INTL = !!($b0 -band 0x40)
        $ret.RG = !!($b0 -band 0x20)
        $ret.TX = switch($b0 -band 0xf) { 0 {"RX"} 0xc {"RXTX"} default { $_ }}
        $b1 = $d[$o+1]
        $ret.scramble = $b1
        $ret.channel = readString $d ($o+2) 2
        $ret.rx_freq = 1000000 + (fromBCD $d[$o+4]) * 10000 + (fromBCD $d[$o+5]) * 100 + (fromBCD $d[$o+6])
        $ret.tx_freq = 1000000 + (fromBCD $d[$o+7]) * 10000 + (fromBCD $d[$o+8]) * 100 + (fromBCD $d[$o+9])
        $b9 = $d[$o+9] -band 15
        $ret.tx_pwr = switch($b9) { 0 {"default"} 0x8 { "1w only" } 0x9 { "1w default" } default { "$_ unknown" } }
        }
        $oo = switch($g) { 0 {0x182} 1 {0x185} 2 {0x180} default {"unknown"} }
        $oo = $oo + [int][math]::Floor($s / 8)
        $ob = 128 -shr ($s % 8)
        $ret.cg = !!($d[$oo] -band $ob)

        $on = switch($g) { 0 {0x3600} 1 {0x3c00} 2 {0x3e00} default {"unknown"}}
        $ret.customName = readstring $d ($on + $s * 0x10) 16
 
        return New-Object psobject -Property $ret
    }

    $group = switch($true) {
        $rg {0}
        $exp {1}
        $wx {2}
        default {0}
    }

    $m = switch($group) { 0 {20} 1 {30} 2 {10} default {"unknown"}}

    if($slot -ne $null) {
        $r = DumpSlot $d $group $slot
            $r | Add-Member MemberSet PSStandardMembers $stdMem
            $r
    } else {
        for($n=0; $n -lt $m; $n=$n+1){
            $r = DumpSlot $d $group $n
            $r | Add-Member MemberSet PSStandardMembers $stdMem
            $r
        }
    }
}



function Set-Hx890RG{
    param([string]$fn = $HX890_FILENAME,
        [switch]$exp,
        [switch]$rg,
        [switch]$wx,
        [parameter(mandatory=$true)] [int]$slot,
        [string]$channel,
        [string]$name,
        [switch]$enable,
        [switch]$disable,

        [switch]$intl,
        [switch]$us,
        [switch]$region,

        [string]$rx_freq,
        [string]$tx_freq,
        [string]$tx
    )
    [int]$s = $slot

    $d = loadBin $fn

    $group = switch($true) {
        $rg {0}
        $exp {1}
        $wx {2}
        default {0}
    }

    $m = switch($group) { 0 {20} 1 {30} 2 {10} default {"unknown"}}

    if ($group -ne 2){
        $o = 0xd00 + $group * 0x200 + $s * 0x10
        if($channel){
            writeString ([ref]$d) ($o + 2) $channel 2
        }

        if($intl -or $us -or $region ){
            $d[$o] = ($d[0] -band 0x0f) -bor $(if ($us) {0x80}) -bor $(if ($intl) {0x40}) -bor $(if ($region) {0x20})
        }

        if($rx_freq){
            if ($rx_freq -notmatch "^1[56]\d\.\d(00|25|50|75)$"){ throw "bad rx" }
            $d[$o+4] = [System.Int16]::Parse($rx_freq[1]) * 0x10 + [System.Int16]::Parse($rx_freq[2])
            $d[$o+5] = [System.Int16]::Parse($rx_freq[4]) * 0x10 + [System.Int16]::Parse($rx_freq[5])
            $d[$o+6] = [System.Int16]::Parse($rx_freq[6]) * 0x10
        }
        if($tx_freq){
            if ($tx_freq -notmatch "^1[56]\d\.\d(00|25|50|75)$"){ throw "bad rx" }
            $d[$o+7] = [System.Int16]::Parse($tx_freq[1]) * 0x10 + [System.Int16]::Parse($tx_freq[2])
            $d[$o+8] = [System.Int16]::Parse($tx_freq[4]) * 0x10 + [System.Int16]::Parse($tx_freq[5])
            $d[$o+9] = [System.Int16]::Parse($tx_freq[6]) * 0x10
        }

        switch($tx){
            "tx" { $d[$o] = ($d[$o] -band 0xf0) -bor 0xc; $d[$o+9] = ($d[$o+9] -band 0xf0)}
            "1w" { $d[$o] = ($d[$o] -band 0xf0) -bor 0xc; $d[$o+9] = ($d[$o+9] -band 0xf0) -bor 9 }
            "1wonly" { $d[$o] = ($d[$o] -band 0xf0) -bor 0xc; $d[$o+9] = ($d[$o+9] -band 0xf0) -bor 8}
            default { $d[$o] = ($d[$o] -band 0xf0); $d[$o+9] = ($d[$o+9] -band 0xf0)}
        }

    }


    if($name) {
        $on = switch($group) { 0 {0x3600} 1 {0x3c00} 2 {0x3e00} default {"unknown"}}
        writeString ([ref]$d) ($on + $s * 0x10) $name 16
    }


    $oo = switch($group) { 0 {0x182} 1 {0x185} 2 {0x180} default {"unknown"} }
    $oo = $oo + [int][math]::Floor($s / 8)
    $ob = 128 -shr ($s % 8)
    if($enable){
        $d[$oo] = $d[$oo] -bor $ob
    }
    if($disable){
        $d[$oo] = $d[$oo] -band (-bnot $ob)
    }

    saveBin $fn $d

}

