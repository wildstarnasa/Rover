Rover
=====

A runtime variable inspector Addon

Rover was originally written by Jon "Bitwise" Wiesman, Lead Client Engineer at Carbine.
Everything listed under Additional Functionality was added by @Sinaloit and Garet Jax.

To open the Rover watch window type: /rover in the chat window.

Methods of adding a watch to Rover:

Event:
```Lua
    Event_FireGenericEvent("SendVarToRover", "WatchName", tSomeVariable, <iOption>)
```

Function:
```Lua
    SendVarToRover("WatchName", tSomeVarible, <iOption>)
```

or

```Lua
    local Rover = Apollo.GetAddon("Rover")
    Rover:AddWatch("WatchName", tSomeVariable, <iOption>)
```

Rover supports the following options for adding watches:

|iOption|Result|
|-------|------|
|Rover.ADD_ALL or 0| Var added even if already present |then the var will be added separately to Rover even if another with the same name is already added.
|Rover.ADD_ONCE or 1| Var added only if not present |
|Rover.ADD_DEFAULT, 2, or no iOption| Var overwrites old value if any|

You'll notice that the first argument to SendVarToRover is the name that you want to Watch to be named inside of Rover, while the second argument is the actual variable to watch, the third optional argument allows you to handle how the variable is added slightly differently as indicated above.

When tables are added to Rover, you will see the "+" sign in the tree control. Expanding the node will cause the table to be expanded at that time. To refresh a variable, you can just collapse and expand its table. Because the values represent a snapshot of the variable when it was added, there is a column that displays when the last time you updated the variable.

 Additional Functionality:

1. Tables are sorted by key names
2. You can add some obvious variables to the tree by clicking on icons
  * _G for the global state
  * Myself for a reference to your character
  * Target for a reference to your target
  * "+ctrl" mode to hover over any clickable window and press <ctrl> to add the window
    * Note: Windows that ignore mouse cannot be obtained this way
  * "+c top" mode to hover over any clickable window and press <ctrl> to add the top level parent
    * Note: Windows that ignore mouse cannot be obtained this way
  * var will open a dialog box where you can enter in a string that will attempt to be converted to a variable.
    * Unique button will use the ADD_ALL option when adding.
3. If you double click on a function it will execute it and post the results in the tree. Please note that:
  * By default it executes the function without any parameters. If they are required, or any other error occurs, you will get the error string printed in the tree.
  * Holding shift while double clicking will prompt for parameters
    1. Parameters are comma separated, lua will attempt to convert what you typed into a variable just as if it was in code
    2. Checkbox to indicate if self variable should be passed as well, Rover tries to make an intelligent decision on this but if it is incorrect you can change it.
    3. Note: self is not a valid argument part for any of the other parameters you would need to indicate what that would be, example: Apollo.GetAddon("MyAddon").myVar would work, self.myVar would not.
  * To refresh the results double-click the function name again
  * Some functions when executed will DESTROY Wildstar.
  * If you want to play a minigame, click on GameLib.UIStartCinematics() and try to restore the UI :)
4. The ability to monitor events
  * Click the "Events" button
  * Click "Add Events"
  * Type the name of the event to monitor
  * Press enter
  * To remove event monitoring either double click the event or click remove all button on the popout
5. Live function calls/Variable access logging for any selected addon/package/table
  * Click the "Logs" button
  * Click "Add Logger"
  * Type the name of the addon/package/table.
  * Search order when adding a log is: Addon, Package, Table.
  * Press enter
  * Logging by default is live access display, shows Target<: or .>AccessedObject where : is used if the accessed object is a function and . if it is anything else.
  * Single click a logger to toggle detailed mode
    1. An "eye" icon will indicate detailed mode is active
    2. Detailed mode logs each access individually and also shows returns the item accessed
    3. Non-Detailed mode only shows the latest access of a function/variable and does not have a reference to that function or the contents of that variable.
  * A (tiny) checkbox between Remove All and Add Logger forces wrapping the target in a new table
    1. This allows the capture of access of all table variables instead of only the ones on the prototype.
    2. May possibly cause instability (Haven't seen any yet but hey this is a warning) so a notice is logged into Rover when a table is wrapped.
  * If its trying to add a table it uses pcall to convert what you typed into lua and then checks if the return is a table.
  * Double click a logged item to remove the logging.
6. "Remove All" button to clear the Rover console
7. You can call SendVarToRover and RemoveVarFromRover even before Rover is fully loaded, and the data will be added to the list anyway. That means that you can debug your addon initialization without setting Rover as dependency.