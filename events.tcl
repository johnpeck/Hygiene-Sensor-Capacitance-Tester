#!/usr/bin/wish

# Folder location for GUI Images
set images "./Figures"

# Global Variables
global events
set programmated_events 0 

package require cmdline

# Packages useful for the GUI

# Img package required for screen captures
package require Img
# BWidget package used for comboboxes
package require BWidget
# TKtable package used for table widgets
package require Tktable
package require Tk

proc push {} {
	# Pocedure to store the ID of the selected port
	set port [.ent get] 
	set portnode $port

	# Set up the channel
	global portchan
	set portchan [port_init $portnode]

	psm_init $portchan

	# Updating the image, the selected port is correct!
	label .lbl2 -image img2
	place .lbl2 -x 350 -y 50
}

proc progr_event {} {
	# Collect the number of events that the user wants to test
	global programmated_events
	set programmated_events [.idwin get] 
}

proc onEnd { programmated_events events } {
	# Box poping up at the very end with the numebr of attempted and succesfully detected events
	#
	# Arguments:
	# programmated_events -- NUmber of events that the user define for this run of the program
	# events -- NUmber of events detected by the system
    tk_messageBox -type ok -icon info -title Information \
    -message "Test completed: Detected $events out of $programmated_events"
}

proc port_init {portnode} {
    # Return a channel to the instrument, or exit if there's a problem
    #
    # Arguments:
    #   portnode -- The filesystem node specified in the push procedure
    set mode "9600,n,8,1"
    try {
    set portchan [open $portnode r+]
    chan configure $portchan \
        -mode $mode \
        -blocking 0 \
        -buffering line \
        -handshake rtscts \
        -encoding binary \
        -translation {binary lf}
    chan puts $portchan "i"
    # There just needs to be some non-zero delay here
    after 100
    set data [read $portchan]
    puts $data
    if { [string first "Syscomp" $data] == -1 } {
        puts "Connected to $portnode, but this is not a CGR-201"
        exit 1
    } 
    } trap {POSIX ENOENT} {} {
	puts "Problem opening $portnode -- it doesn't exist"
	exit 1
    } trap {POSIX EACCES} {} {
	puts "Problem opening $portnode -- permission denied"
	exit 1
    }
    return $portchan
}

proc schedule_activation {portchan} {
	# Schedule the activation of the Syscomp CGR-201. Specifically:
	#
	# -- Activate outputs to drive the switch and to power the light sensor circuit.
	# -- Define the timing to collect data from the light sensor circuit in the digital input.
	
	set events 0
	global programmated_events

    # Activate Digital Output to power light sensor
    chan puts $portchan "O 1" 
    after 5
    chan puts $portchan "G 000 000 050 000"
    after 5

    # Starting collecting data from digital input
    set incomingData [read $portchan]

    # Convert the data bytes into signed integers
    if { [llength {$incomingData}] > 0 } {
        binary scan $incomingData c* signed
    }
	
    for {set i 0} {$i < $programmated_events} {incr i} {
    	# Only the light sensor circuit have power
        chan puts $portchan "O 1"
        after 2000
        # Avtivating the switch
        chan puts $portchan "O 3"
        after 100
        for {set j 0} {$j < 50} {incr j} {
        	# Serial command to receive data from digital input
            chan puts $portchan "N"
            after 100
            set incomingData [read $portchan]
            if { [llength {$incomingData}] > 0 } {
                binary scan $incomingData c* signed
                set light 0
                # First charachter is capital I, which is the response type for digital input request.
                scan $incomingData "%c%c" out light
                # If it is not 0, it means that one of the digital input is 1
                if {$light != 0} {
                	# Increasing the number of events detected. To avoid double detection the digital input is not checked anymore (the LED blinks to time)
                    incr events
                    break
                }
            }
        }
        set att [expr $i+1]
        puts "Attempted events: $att, Detected events: $events"
    }  
    onEnd $programmated_events $events
}

proc send_command {portchan command} {
    # Send a command to the PSM-101
    #
    # Arguments:
    #   portchan -- Communication channel
    #   command -- Command string to be sent
    puts $portchan $command
    after 1
}

proc psm_init {portchan} {
    # Initialize the PSM-101
    #
    # Arguments:
    #   portchan -- Communications channel
    send_command $portchan "V500"
    send_command $portchan "e"
}

## GUI label, insert your port here
label .lab -text "Enter port:"
entry .ent 
button .but -text "Check" -command "push"
pack .ent
pack .but
place .lab -x 10 -y 10
place .ent -x 10 -y 50 

# By default it is set to COM5, port of CGR-201
.ent insert end "COM5"
set portnode "COM5"
place .but -x 250 -y 50 

# Stop picture preloaded
image create photo img1 -file "$images/StopButton.gif"
image create photo img2 -file "$images/RecordButton.gif"
label .lbl1 -image img1
place .lbl1 -x 350 -y 50

# GUI label, insert your ID here
label .id -text "Programmated Events"
entry .idwin 
button .idbut -text "Set" -command "progr_event"
pack .idwin
pack .idbut
place .id -x 10 -y 100
place .idwin -x 10 -y 140 
place .idbut -x 250 -y 140 

# Quit and Start button to start and conclude the execution
button .quit -text "Quit" -command { exit }
button .start -text "Start" -command { schedule_activation $portchan }
place .start -x 50 -y 210 
place .quit -x 150 -y 210 


# Window creation
wm title . "Capacitive Test" 
wm geometry . 450x280+100+100