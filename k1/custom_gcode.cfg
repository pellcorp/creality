[gcode_macro START_PRINT]
gcode:
	{% set BED_TEMP=params.BED_TEMP|default(55)|float %}
	{% set EXTRUDER_TEMP=params.EXTRUDER_TEMP|default(195)|float %}
	
	# Home the printer
	G90
	M83
	G28
	
	# Preheat the bed
	M140 S{BED_TEMP}
	M190 S{BED_TEMP}
	
	BED_MESH_CALIBRATE ADAPTIVE=1 ADAPTIVE_MARGIN=5
	
	# Heat the extruder to the desired temperature
	M104 S{EXTRUDER_TEMP}
	M109 S{EXTRUDER_TEMP}
	
	# Prime line sequence
	G92 E0				     	      # Reset Extruder
    	G0 Z2.0 F{ 50 * 60 }    	      # Move Z Axis to travel height
    	G0 X0.1 Y20 F{ 100 * 60 } 	      # Move to start position
    	G0 Z0.35 F{ 2 * 60 } 	          # Move to extrude height
    	G1 X0.1 Y200.0 F{ 50 * 60 } E15	  # Draw the first line
    	G0 X0.5 Z0.35				      # Move to side a little
    	G1 Y20 E20				          # Draw the second line
    	G1 Y195 E-1				          # Wipe
    	G1 Z5                             # Move Z Axis up to travel height
    	G1 E1           	              # De-retract
    	G92 E0				              # Reset Extruder

[gcode_macro END_PRINT]
description: End the actual running print
gcode:
  _CLIENT_RETRACT LENGTH=5
  TURN_OFF_HEATERS

  # clear pause_next_layer and pause_at_layer as preparation for next print
  SET_PAUSE_NEXT_LAYER ENABLE=0
  SET_PAUSE_AT_LAYER ENABLE=0 LAYER=0
  _TOOLHEAD_PARK_PAUSE_CANCEL {rawparams}


# emergency situation calls for drastic
[gcode_shell_command emergency_factory_reset]
command: /usr/data/pellcorp/k1/wipe.sh "all"
timeout: 5.
verbose: True

[gcode_macro EMERGENCY_FACTORY_RESET]
gcode:
    RUN_SHELL_COMMAND CMD=emergency_factory_reset
