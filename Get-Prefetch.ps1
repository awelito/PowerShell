################################################################################
#    Name: Get-Prefetch.ps1
# Purpose: Queries the local computer for Prefetch Files, and Parses information
#          from the Prefetch Data Structure.
# Version: 1.0
#    Date: 14Oct2013
#  Author: Jared Atkinson (www.invoke-ir.com)
#   Legal: Public domain, no guarantees or warranties provided.
################################################################################
##################################################################################
# TO-DO
##################################################################################
# Add Section D Support Beyond BTIME
# Add Support for Multiple Devices in Section D
# Handle Windows 8 Timestamps
# Add Hashing of All Prefetched Files
###################################################################################
# Load Prefetch Enumeration
###################################################################################
function Get-Prefetch{
    [CmdletBinding()]
    Param(
        [Parameter()]
            [string[]]$ComputerName
    )
    $scriptblock = {
        $codeXP = @"
            //Prefetch File Structures
            public enum Prefetch
            {
                magic_b = 4,
                magic_e = 7,
                exename_b = 16,
                exename_e = 75,
                hash_b = 76,
                hash_e = 79,
                depcount_b = 88,
                depcount_e = 91,
                cOffset_b = 100,
                cOffset_e = 103,
                cLength_b = 104,
                cLength_e = 107,
                dOffset_b = 108,
                dOffset_e = 111,
                devcount_b = 112,
                devcount_e = 115,
                dLength_b = 116,
                dLength_e = 119,
                atime_b = 120,
                atime_e = 127,
                runcount_b = 144,
                runcount_e = 147,
            }
"@

        $codeWin7 = @"
            //Prefetch File Structures
            public enum Prefetch
            {
                magic_b = 4,
                magic_e = 7,
                exename_b = 16,
                exename_e = 75,
                hash_b = 76,
                hash_e = 79,
                depcount_b = 88,
                depcount_e = 91,
                cOffset_b = 100,
                cOffset_e = 103,
                cLength_b = 104,
                cLength_e = 107,
                dOffset_b = 108,
                dOffset_e = 111,
                devcount_b = 112,
                devcount_e = 115,
                dLength_b = 116,
                dLength_e = 119,
                dCount_b = 120,
                dCount_e = 123,
                atime_b = 128,
                atime_e = 135,
                runcount_b = 152,
                runcount_e = 155,
            }
"@

        $codeWin8 = @"
            //Prefetch File Structures
            public enum Prefetch
            {
                magic_b = 4,
                magic_e = 7,
                exename_b = 16,
                exename_e = 75,
                hash_b = 76,
                hash_e = 79,
                depcount_b = 88,
                depcount_e = 91,
                cOffset_b = 100,
                cOffset_e = 103,
                cLength_b = 104,
                cLength_e = 107,
                dOffset_b = 108,
                dOffset_e = 111,
                devcount_b = 112,
                devcount_e = 115,
                dLength_b = 116,
                dLength_e = 119,
                dCount_b = 120,
                dCount_e = 123,
                atime_b = 128,
                atime_e = 135,
                atime2_b = 136,
                atime2_e = 143,
                atime3_b = 144,
                atime3_e = 151,
                atime4_b = 152,
                atime4_e = 159,
                atime5_b = 160,
                atime5_e = 167,
                atime6_b = 168,
                atime6_e = 175,
                atime7_b = 176,
                atime7_e = 183,
                atime8_b = 184,
                atime8_e = 191,        
                runcount_b = 208,
                runcount_e = 211,
            }
"@

        try{
            [Prefetch].IsPublic | Out-Null
        }catch{
            $OS = (Get-WmiObject win32_operatingsystem).Version
            if($OS -ge 6.2){
                Add-Type -TypeDefinition $codeWin8
            }elseif($OS -ge 6.0){
                Add-Type -TypeDefinition $codeWin7
            }elseif($OS -ge 5.0){
                Add-Type -TypeDefinition $codeXP
            }
        }
        ###################################################################################
        #
        ###################################################################################
        function ConvertBytesToHex($Bytes){
            $HexBytes = $NULL
            foreach($l in $Bytes){
                $HexBytes += "{0:X2}" -f $l
            }
            return $HexBytes
        }

        function ConvertBytesToDecimal($Bytes, $Long=$FALSE){
            $HexBytes = ConvertBytesToHex($Bytes)
            if($Long){
                if($HexBytes.Length -lt 16){
                    $HexBytes = $HexBytes.Insert(0,'00000000')
                }
                $Decimal = [Convert]::ToInt64($HexBytes, 16)
            }else{
                $Decimal = [Convert]::ToInt32($HexBytes, 16)
            }
            return $Decimal
        }

        function ConvertToTimeStamp($bytes){
            $decimaltimestamp = ConvertBytesToDecimal $bytes $TRUE
            $timestamp = [datetime]::FromFileTime($decimaltimestamp)
            return $timestamp
        }

        function HashFile($path){
            $crypto = [System.Security.Cryptography.MD5]::Create()
            $data = [System.IO.File]::ReadAllBytes($path)
            $MD5 = [System.BitConverter]::ToString($crypto.ComputeHash($data)).Replace('-','')
            Return $MD5
        }
        ###################################################################################
        #
        ###################################################################################
        function Parse-Unicode($Bytes,$Section=$FALSE){
            $Encoder = New-Object System.Text.UnicodeEncoding
            if($Section){
                DecodeBytes $Bytes $Encoder $TRUE
            }else{
                DecodeBytes $Bytes $Encoder
            }
        }
        function Parse-ASCII($Bytes,$Section=$FALSE){
            $Encoder = New-Object System.Text.ASCIIEncoding
            if($Section){
                DecodeBytes $Bytes $Encoder $TRUE
            }else{
                DecodeBytes $Bytes $Encoder
            }
        }

        function DecodeBytes($Bytes, $Encoder, $Section=$FALSE){
            [string]$word = $Encoder.GetString($Bytes)
            if(!($Section)){
                if($word.indexof($NULL) -ne -1){
                    $index = $word.indexof($NULL)
                    $word = $word.substring(0,$index)
                }
            }
            return $word
        }
        ###################################################################################
        # Function to Differentiate between OS Version
        ###################################################################################
        function TestPrefetchVersion($FileBytes){
            # All Prefetch Files have the ASCII String SCCA from byte offset 0x04 to 0x07
            [string]$PrefetchSignature = 'SCCA'
            # The first 8 bytes of a prefetch file provide the signature which can be used to determine 
            # the major version of the file's OS
            #Convert bytes 0x04 to 0x07 to ASCII for string comparison
            $FileSignature = Parse-ASCII($FileBytes[0x04..0x07])
            # Windows Major version 6 Prefetch Files begin with 0x17 while Major version 5 begins with 0x11 
            # (If the file does not match this signature it is not a prefetch file)
            if($FileSignature -eq $PrefetchSignature){
                switch($FileBytes[0x00]){
                    0x1A{$PrefetchVersion = 'Win8'}
                    0x17{$PrefetchVersion = 'Win7'}
                    0x11{$PrefetchVersion = 'XP'}
                    default{$PrefetchVersion = $NULL}
                }
            }
            return $PrefetchVersion
        }
        ###################################################################################
        # Enumerate Prefetch Files on System
        ###################################################################################
        $PrefetchPath = 'C:\WINDOWS\Prefetch\'
        $PrefetchFiles = Get-ChildItem $PrefetchPath
        foreach($File in $PrefetchFiles){
            ###################################################################################
            # Read the contents of all files that end in .pf within the PrefetchPath
            ###################################################################################
            if($File.Name -match '.pf'){
                $FullFileName = $PrefetchPath + $File.Name
                $FileBytes = [System.IO.File]::ReadAllBytes($FullFileName)
                $PrefetchVersion = TestPrefetchVersion($FileBytes)
                ###################################################################################
                # If the file has a valid Prefetch Header then begin parsing
                ###################################################################################
                if($PrefetchVersion -ne $NULL){
                    $EXENameBytes = $FileBytes[[prefetch]::exename_b..[prefetch]::exename_e]
                    $PathHashBytes = $FileBytes[[prefetch]::hash_e..[prefetch]::hash_b]
                    $DependencyCountBytes = $FileBytes[[prefetch]::depcount_e..[prefetch]::depcount_b]
                    $SectionCOffsetBytes = $FileBytes[[prefetch]::cOffset_e..[prefetch]::cOffset_b]
                    $SectionCLengthBytes = $FileBytes[[prefetch]::cLength_e..[prefetch]::cLength_b]
                    $SectionDOffestBytes = $FileBytes[[prefetch]::dOffset_e..[prefetch]::dOffset_b]
                    $DeviceCountBytes = $FileBytes[[prefetch]::devcount_e..[prefetch]::devcount_b]
                    $SectionDLengthBytes = $FileBytes[[prefetch]::dLength_e..[prefetch]::dLength_b]
                    $AtimeBytes = $FileBytes[[prefetch]::atime_e..[prefetch]::atime_b]
                    $RunCountBytes = $FileBytes[[prefetch]::runcount_e..[prefetch]::runcount_b]
                    #$SectionDCountBytes = 
                    $EXEName = Parse-Unicode($EXENameBytes)
                    $PathHash = (ConvertBytesToHex($PathHashBytes)).Insert(4,'-')
                    $DependencyCount = ConvertBytesToDecimal($DependencyCountBytes)
                    $SectionCOffset = ConvertBytesToDecimal($SectionCOffsetBytes)
                    $SectionCLength = ConvertBytesToDecimal($SectionCLengthBytes)
                    $SectionDOffset = ConvertBytesToDecimal($SectionDOffestBytes)
                    $DeviceCount = ConvertBytesToDecimal($DeviceCountBytes)
                    $SectionDLength = ConvertBytesToDecimal($SectionDLengthBytes)
                    $ATime = (ConvertToTimeStamp($ATimeBytes)).ToUniversalTime()
                    $RunCount = ConvertBytesToDecimal($RunCountBytes)
                    ##################################################################################
                    # Building Sections C and D
                    ##################################################################################
                    $SectionCEnd = $SectionCOffset+$SectionCLength-1
                    $SectionC = $FileBytes[$SectionCOffset..$SectionCEnd]
                    $SectionDEnd = $SectionDOffset+$SectionDLength-1
                    $SectionD = $FileBytes[$SectionDOffset..$SectionDEnd]
                    ##################################################################################
                    # SECTION C (File Dependencies)
                    ##################################################################################
                    $DependencyFiles = (Parse-Unicode $SectionC $TRUE).Replace($NULL,"`n").TrimEnd("`n")
                    $DependencyArray = $DependencyFiles.Split("`n")
                    Foreach($d in $DependencyArray){
                        if($d -match $EXEName -and $d -notmatch '.EXE.' -and $d -notmatch '.SCR.MUI'){
                            $EXEPathRaw = $d
                            break
                        }
                    }
                    ##################################################################################
                    # SECTION D (Device/Directory Dependencies)
                    ##################################################################################
                    #$SectionDSub1 = $SectionD[0x00..0x68]
                    #$VolStringOffsetBytes = $SectionD[0x03..0x00]
                    #$VolStringLengthBytes = $SectionD[0x07..0x04]
                    $btimebytes = $SectionD[0x0F..0x08]
                    $VolSerialNumBytes = $SectionD[0x13..0x10]
                    #$SubSectionOffsetBytes = $SectionD[0x17..0x14]
                    #$SubSectionLengthBytes = $SectionD[0x1B..0x18]
                    #$PrefetchDirectoriesOffsetBytes = $SectionD[0x1F..0x1C]
                    #$PrefetchDirectoryCountBytes = $SectionD[0x23..0x20]

                    #$VolStringOffset = ConvertBytesToDecimal($VolStringOffsetBytes)
                    #$VolStringLength = ConvertBytesToDecimal($VolStringLengthBytes)
                    $btime = ConvertToTimeStamp($btimebytes)
                    $VolSerialNum = ConvertBytesToDecimal $VolSerialNumBytes $TRUE
                    #$SubSectionOffset = ConvertBytesToDecimal($SubSectionOffsetBytes)
                    #$SubSectionLength = ConvertBytesToDecimal($SubSectionLengthBytes)
                    #$PrefetchDirectoriesOffset = ConvertBytesToDecimal($PrefetchDirectoriesOffsetBytes)
                    #$PrefetchDirectoryCount = ConvertBytesToDecimal($PrefetchDirectoryCountBytes)
                    ##################################################################################
                    # Executed Program
                    ##################################################################################
                    $DriveLetter = (Get-WmiObject win32_Volume | Where-Object {$_.SerialNumber -eq $VolSerialNum}).Name
                    $EXEPath = $EXEPathRaw.Replace('\DEVICE\HARDDISKVOLUME1\',$DriveLetter)
                    $MD5 = HashFile($EXEPath)
                    $pbtime = [system.io.file]::GetCreationTimeUtc($EXEpath)
                    $pctime = [system.io.file]::GetLastWriteTimeUtc($EXEPath)
                    ##################################################################################
                    # Create the Object
                    ##################################################################################
                    $props = @{
                        'Name' = $EXEName;
                        'Path' = $EXEPath;
                        'MD5' = $MD5;
                        'PathHash' = $PathHash;
                        'DependencyCount' = $DependencyCount;
                        'PrefetchAccessTime' = $atime;
                        'PrefetchBornTime' = $btime;
                        'ProgramBornTime' = $pbtime;
                        'ProgramChangeTime' = $pctime;
                        'DeviceCount' = $DeviceCount;
                        'RunCount' = $RunCount;
                        'DependencyFiles' = $DependencyFiles
                    }
                    $obj = New-Object -TypeName PSObject -Property $props
                    Write-Output $obj
                }
            }
        }
    }
    Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptblock
}

Get-Prefetch -ComputerName localhost
