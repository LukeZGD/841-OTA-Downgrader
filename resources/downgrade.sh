#!/bin/bash

iDeviceRestore() {
    Log "Proceeding to idevicerestore... (Enter root password of your PC/Mac when prompted)"
    [[ $platform == "macos" ]] && sudo codesign --sign - --force --deep $idevicerestore
    mkdir shsh
    mv $SHSH shsh/${UniqueChipID}-${ProductType}-${OSVer}.shsh
    $idevicerestore -ewy $IPSWRestore.ipsw
    if [[ $platform == "macos" && $? != 0 ]]; then
        Log "An error seems to have occurred when running idevicerestore."
        Echo "* If this is the \"Killed: 9\" error or similar, try these steps:"
        Echo "* Using Terminal, cd to where the script is located, then run"
        Echo "* sudo codesign --sign - --force --deep resources/tools/idevicerestore_macos"
    fi
}

FRBaseband() {
    local BasebandSHA1L
    
    if [[ $DeviceProc == 7 ]] || [[ $ProductType == "iPhone5,1" && $Baseband5 != 0 ]]; then
        mkdir -p saved/baseband 2>/dev/null
        cp -f $IPSWRestore/Firmware/$Baseband saved/baseband
    elif [[ ! -e saved/baseband/$Baseband ]]; then
        Log "Downloading baseband..."
        $partialzip $BasebandURL Firmware/$Baseband $Baseband
        $partialzip $BasebandURL BuildManifest.plist BuildManifest.plist
        mkdir -p saved/$ProductType saved/baseband 2>/dev/null
        mv $Baseband saved/baseband
        mv BuildManifest.plist saved/$ProductType
        BuildManifest="saved/$ProductType/BuildManifest.plist"
    else
        BuildManifest="saved/$ProductType/BuildManifest.plist"
    fi
    
    BasebandSHA1L=$(shasum saved/baseband/$Baseband | awk '{print $1}')
    if [[ ! -e $(ls saved/baseband/$Baseband) || $BasebandSHA1L != $BasebandSHA1 ]]; then
        rm -f saved/baseband/$Baseband saved/$ProductType/BuildManifest.plist
        Error "Downloading/verifying baseband failed. Please run the script again"
    fi
}

FutureRestore() {
    local ExtraArgs
    local futurerestore
    
    if [[ $DeviceProc == 7 ]]; then
        ExtraArgs="-s $IPSWRestore/Firmware/all_flash/$SEP -m $BuildManifest"
        futurerestore=$futurerestore2
    else
        ExtraArgs="--use-pwndfu"
        futurerestore=$futurerestore1
    fi
    
    Log "Proceeding to futurerestore..."
    if [[ $Baseband == 0 ]]; then
        Log "Device $ProductType has no baseband"
        $futurerestore -t $SHSH --no-baseband $ExtraArgs "$IPSWRestore.ipsw"
    else
        FRBaseband
        $futurerestore -t $SHSH -b saved/baseband/$Baseband -p $BuildManifest $ExtraArgs "$IPSWRestore.ipsw"
    fi
}

Downgrade() {
    local IPSWCustomW
    local IPSWExtract
    local IPSWSHA1
    local IPSWSHA1L
    local Jailbreak
    local Verify
    
    if [[ $OSVer == "Other" ]]; then
        if [[ $platform == "linux" ]]; then
            IPSW="$(zenity --file-selection --file-filter='IPSW | *.ipsw' --title="Select IPSW file")"
            IPSW="${IPSW%?????}"
            Log "Selected IPSW file: $IPSW"
            SHSH="$(zenity --file-selection --file-filter='SHSH | *.shsh *.shsh2' --title="Select SHSH file")"
            Log "Selected SHSH file: $SHSH"
        else
            Echo "* Move/copy the IPSW and SHSH files to the directory where the script is located"
            Echo "* When entering the names of IPSW and SHSH, enter the full name including the file extension"
            Echo "* Remember to create a backup of the SHSH"
            read -p "$(Input 'Enter name of IPSW file:')" IPSW
            IPSW="$(basename $IPSW .ipsw)"
            read -p "$(Input 'Enter name of SHSH file:')" SHSH
        fi

    elif [[ $Mode == "Downgrade" && $DeviceProc != 7 ]]; then
        read -p "$(Input 'Jailbreak the selected iOS version? (Y/n):')" Jailbreak
        
        if [[ $Jailbreak != 'N' && $Jailbreak != 'n' ]]; then
            Jailbreak=1
            if [[ $ProductType == "iPhone4,1" || $ProductType == "iPad2,4" ||
                  $ProductType == "iPad2,5" || $ProductType == "iPad2,6" ||
                  $ProductType == "iPad2,7" || $ProductType == "iPod5,1" ]] ||
               [[ $ProductType == "iPad3"* && $DeviceProc == 5 ]]; then
                Log "Using daibutsu jailbreak"
                JBDaibutsu=1
            fi
        fi
    fi
    
    if [[ $Mode == "Downgrade" && $ProductType == "iPhone5,1" && $Jailbreak != 1 ]]; then
        Echo "* By default, iOS-OTA-Downgrader now flashes the iOS 8.4.1 baseband to iPhone5,1"
        Echo "* Flashing the latest baseband is still available as an option but beware of problems it may cause"
        Echo "* There are potential network issues that with the latest baseband when used on iOS 8.4.1"
        read -p "$(Input 'Flash the latest baseband? (y/N) (press Enter/Return if unsure):')" Baseband5
        if [[ $Baseband5 == 'Y' || $Baseband5 == 'y' ]]; then
            Baseband5=0
        else
            BasebandURL=$(cat $Firmware/12H321/url)
            Baseband="Mav5-8.02.00.Release.bbfw"
            BasebandSHA1="db71823841ffab5bb41341576e7adaaeceddef1c"
        fi
    fi
    
    if [[ $OSVer != "Other" ]]; then
        [[ $DeviceProc != 7 ]] && SaveOTABlobs
    
        IPSW="${IPSWType}_${OSVer}_${BuildVer}_Restore"
        IPSWCustom="${IPSWType}_${OSVer}_${BuildVer}_Custom"
        if [[ $Jailbreak != 1 && $DeviceProc != 7 ]]; then
            Selection=("futurerestore" "idevicerestore")
            Echo "* Select 1 (futurerestore) if unsure"
            Echo "* Select 2 (idevicerestore) if you experience issues with futurerestore"
            Input "Select restore tool to use:"
            select opt in "${Selection[@]}"; do
            case $opt in
                "idevicerestore" ) IPSWCustom="${IPSWCustom}W"; IPSWCustomW=1; break;;
                *) break;;
                esac
            done
        fi

        if [[ ! -e "$IPSW.ipsw" && ! -e "$IPSWCustom.ipsw" ]]; then
            Log "iOS $OSVer IPSW cannot be found."
            Echo "* If you already downloaded the IPSW, did you put it in the same directory as the script?"
            Echo "* Do NOT rename the IPSW as the script will fail to detect it"
            Log "Downloading IPSW... (Press Ctrl+C to cancel)"
            curl -L $(cat $Firmware/$BuildVer/url) -o tmp/$IPSW.ipsw
            mv tmp/$IPSW.ipsw .
        fi
    
        if [[ ! -e "$IPSWCustom.ipsw" && $IPSWCustomW == 1 ]]; then
            Verify=1
        elif [[ $Jailbreak == 1 || $DeviceProc == 7 ]]; then
            [[ ! -e "$IPSWCustom.ipsw" ]] && Verify=1
        elif [[ $Jailbreak != 1 && $IPSWCustomW != 1 ]]; then
            Verify=1
        fi
    
        if [[ $Verify == 1 ]]; then
            Log "Verifying IPSW..."
            IPSWSHA1=$(cat $Firmware/$BuildVer/sha1sum)
            Log "Expected SHA1sum: $IPSWSHA1"
            IPSWSHA1L=$(shasum $IPSW.ipsw | awk '{print $1}')
            Log "Actual SHA1sum:   $IPSWSHA1L"
            if [[ $IPSWSHA1L != $IPSWSHA1 ]]; then
                Error "Verifying IPSW failed. Your IPSW may be corrupted or incomplete." \
                "Delete/replace the IPSW and run the script again"
            fi
        elif [[ -e "$IPSWCustom.ipsw" ]]; then
            Log "Found existing Custom IPSW. Skipping IPSW verification."
            Log "Setting restore IPSW to: $IPSWCustom.ipsw"
            IPSWRestore=$IPSWCustom
        fi
    
        if [[ $DeviceState == "Normal" && $iBSSBuildVer == $BuildVer ]]; then
            Log "Extracting iBSS from IPSW..."
            mkdir -p saved/$ProductType 2>/dev/null
            unzip -o -j $IPSW.ipsw Firmware/dfu/$iBSS.dfu -d saved/$ProductType
        fi
    else
        IPSWCustom=0
    fi
    
    [[ $DeviceState == "Normal" ]] && kDFU

    if [[ $Jailbreak == 1 || $IPSWRestore == $IPSWCustom || $IPSWCustomW == 1 ]]; then
        [[ $Jailbreak == 1 || $IPSWCustomW == 1 ]] && IPSW32
        IPSWExtract="$IPSWCustom"
    else
        IPSWExtract="$IPSW"
    fi

    Log "Extracting IPSW: $IPSWExtract.ipsw"
    unzip -q "$IPSWExtract.ipsw" -d "$IPSWExtract"/
    
    if [[ $DeviceProc == 7 ]]; then
        IPSW64
        pwnREC
        SaveOTABlobs
    elif [[ $Jailbreak != 1 && $OSVer != "Other" && $IPSWCustomW != 1 ]]; then
        Log "Preparing for futurerestore... (Enter root password of your PC/Mac when prompted)"
        cd resources
        [[ $platform == "linux" ]] && $SimpleHTTPServer || $SimpleHTTPServer &
        ServerRunning=1
        cd ..
    fi
    
    if [[ ! $IPSWRestore ]]; then
        Log "Setting restore IPSW to: $IPSW.ipsw"
        IPSWRestore="$IPSW"
    fi
    
    if [[ $Jailbreak == 1 || $IPSWCustomW == 1 ]]; then
        iDeviceRestore
    else
        FutureRestore
    fi
    
    echo
    Log "Restoring done!"
    Log "Downgrade script done!"
}
