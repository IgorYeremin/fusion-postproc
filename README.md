# fusion-postproc

Fusion 360 post processor script for the hacklab.to laser cutter.

## Insallation
### Windows
* Copy `hacklab-laser.cps` into `%APPDATA%\Autodesk\Fusion 360 CAM\Posts`

## Use
* Enable Preview feature "CAM - Waterjet/Laser/Plasma cutter support" in the user preferences menu
* Create Waterjet/Laser/Plasma step in CAM mode, set type to "Laser cutting"
* Select Cutting Mode: Through or Etch (Etch just means no kerf compensation, not raster)
* Set Kerf Width, and Cutting Feedrate
* Select curves to cut, by default holes should cut counter-clockwise, positive parts - clockwise. Flip direction by clicking red arrow
* Ignore heights tab
* Sideways compensation: Left = CCW holes, CW positives, Right is inverse. Center disables kerf compensation.
* "In control" mode lets you edit the output file to change kerf later (but only make it smaller, not bigger), "In computer" does not
* Lead-in and out are required if using "In control" compensation mode, but can be disabled for "In computer"
* Save step and repeat to create more if needed
* Select all steps to put into one file and click the "Post Process" button
* Click "Setups" button on post processor dialog, and select "User Personal Posts"
* Select "hacklab-laser" post configuration
* Set job name, comment, etc
* Post
* Feed resulting .ngc file to hacklab laser
