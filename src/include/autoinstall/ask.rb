# encoding: utf-8

# File:	clients/autoinst_post.ycp
# Package:	Auto-installation
# Author:      Anas Nashif <nashif@suse.de>
# Summary:	This module finishes auto-installation and configures
#		the system as described in the profile file.
#
# $Id$
module Yast
  module AutoinstallAskInclude
    def initialize_autoinstall_ask(include_target)
      Yast.import "Profile"
      Yast.import "UI"
      Yast.import "Label"
      Yast.import "Stage"
      Yast.import "Popup"
    end

    def path2pos(pa)
      pos = []
      Builtins.foreach(Builtins.splitstring(pa, ",")) do |p|
        if Builtins.regexpmatch(p, "^[1,2,3,4,5,6,7,8,9,0]+$")
          index = Builtins.tointeger(p)
          pos = Builtins.add(pos, index)
        else
          pos = Builtins.add(pos, p)
        end
      end
      deep_copy(pos)
    end

    def createWidget(widget, frametitle)
      widget = deep_copy(widget)
      ret = Left(widget)

      deep_copy(ret)
    end

    def askDialog
      mod = false

      dialogs = {}
      keys = []
      dialog_cnt = 0
      history = []

      Builtins.foreach(
        Builtins.sort(
          Ops.get_list(Profile.current, ["general", "ask-list"], [])
        ) do |x, y|
          Ops.less_than(
            Ops.get_integer(x, "element", 0),
            Ops.get_integer(y, "element", 0)
          )
        end
      ) do |ask|
        if Stage.initial && Ops.get_string(ask, "stage", "initial") == "initial" ||
            Stage.cont && Ops.get_string(ask, "stage", "initial") == "cont"
          Ops.set(
            dialogs,
            Ops.get_integer(ask, "dialog", dialog_cnt),
            Builtins.add(
              Ops.get(dialogs, Ops.get_integer(ask, "dialog", dialog_cnt), []),
              ask
            )
          )
          if !Builtins.contains(
              keys,
              Ops.get_integer(ask, "dialog", dialog_cnt)
            )
            keys = Builtins.add(
              keys,
              Ops.get_integer(ask, "dialog", dialog_cnt)
            )
          end
          dialog_cnt = Ops.add(dialog_cnt, 1) if !Builtins.haskey(ask, "dialog")
        end
      end

      keys = Builtins.sort(keys)

      dialogCounter = 0
      dialog_nr = Ops.get(keys, dialogCounter, -1)
      jumpToDialog = -2
      if Ops.greater_than(SCR.Read(path(".target.size"), "/tmp/next_dialog"), 0)
        s = Convert.to_string(
          SCR.Read(path(".target.string"), "/tmp/next_dialog")
        )
        s = Builtins.filterchars(s, "-0123456789")
        jumpToDialog = Builtins.tointeger(s)
        SCR.Execute(path(".target.remove"), "/tmp/next_dialog")
        Builtins.y2milestone(
          "next_dialog file found. Set dialog to %1",
          jumpToDialog
        )
      end
      while dialog_nr != -1
        Builtins.y2milestone("dialog_nr = %1", dialog_nr)
        Builtins.y2milestone("dialogCounter = %1", dialogCounter)
        Builtins.y2milestone("jumpToDialog  %1", jumpToDialog)
        helptext = ""
        title = ""
        back_label = Label.BackButton
        ok_label = Label.OKButton
        dialog_term = VBox()
        help_term = Empty()
        title_term = Empty()
        element_cnt = 0
        timeout = 0
        min_width = 0
        min_height = 0
        history = Builtins.add(history, dialog_nr)
        frameBuffer = nil
        frameBufferVBox = nil
        frameBufferTitle = ""
        Builtins.foreach(
          Convert.convert(
            Ops.get(dialogs, dialog_nr, []),
            :from => "list",
            :to   => "list <map>"
          )
        ) do |ask|
          pathStr = Ops.get_string(ask, "path", "")
          type = Ops.get_string(ask, "type", "")
          question = Ops.get_string(ask, "question", pathStr)
          frametitle = Ops.get_string(ask, "frametitle", "")
          entry_id = Builtins.sformat(
            "%1_%2",
            dialog_nr,
            Ops.get_integer(ask, "element", element_cnt)
          )
          element_cnt = Ops.add(element_cnt, 1)
          s = Ops.get_list(ask, "selection", [])
          helptext = Ops.add(helptext, Ops.get_string(ask, "help", ""))
          title = Ops.get_string(ask, "title", "")
          back_label = Ops.get_string(ask, "back_label", back_label)
          ok_label = Ops.get_string(ask, "ok_label", ok_label)
          timeout = Ops.get_integer(ask, "timeout", 0)
          mod = true
          if Ops.greater_than(Ops.get_integer(ask, "width", 0), min_width)
            min_width = Ops.get_integer(ask, "width", 0)
          end
          if Ops.greater_than(Ops.get_integer(ask, "height", 0), min_height)
            min_height = Ops.get_integer(ask, "height", 0)
          end

          #
          # Script to calculate the default value (optional)
          #
          if Builtins.haskey(ask, "default_value_script")
            interpreter = Ops.get_string(
              ask,
              ["default_value_script", "interpreter"],
              "shell"
            )
            if interpreter == "shell"
              interpreter = "/bin/sh"
            elsif interpreter == "perl"
              interpreter = "/usr/bin/perl"
            end
            scriptPath = Builtins.sformat(
              "%1/%2",
              AutoinstConfig.tmpDir,
              "ask_default_value_script"
            )
            SCR.Write(
              path(".target.string"),
              scriptPath,
              Ops.get_string(ask, ["default_value_script", "source"], "")
            )
            out = Convert.to_map(
              SCR.Execute(
                path(".target.bash_output"),
                Ops.add(Ops.add(interpreter, " "), scriptPath),
                {}
              )
            )
            Builtins.y2debug("%1", out)
            if Ops.get_integer(out, "exit", -1) == 0
              Ops.set(
                ask,
                "default",
                Ops.get_string(
                  out,
                  "stdout",
                  Ops.get_string(ask, "default", "")
                )
              )
            end
            Builtins.y2debug(
              "default for '%1' is '%2' after script execution with exit code %3 (%4)",
              question,
              Ops.get_string(ask, "default", "__undefined__"),
              Ops.get_integer(out, "exit", -1),
              Ops.get_string(out, "stderr", "")
            )
          end

          #
          # Start to handle questions: widgets creation (checkbox, combobox)
          #
          dlg = Dummy()
          if type == "boolean"
            on = Ops.get(ask, "default") == "true" ? true : false
            widget = CheckBox(Id(entry_id), Opt(:notify), question, on)
            dlg = createWidget(widget, frametitle)
          elsif type == "symbol"
            dummy = []
            Builtins.foreach(s) do |e|
              on = Ops.get_symbol(e, "value", :edge_of_dawn) ==
                Ops.get(ask, "default") ? true : false
              dummy = Builtins.add(
                dummy,
                Item(
                  Id(Ops.get_symbol(e, "value", :none)),
                  Ops.get_string(e, "label", ""),
                  on
                )
              )
            end
            widget = ComboBox(Id(entry_id), Opt(:notify), question, dummy)
            dlg = createWidget(widget, frametitle)
          elsif type == "static_text"
            widget = Label(Id(entry_id), Ops.get_string(ask, "default", ""))
            dlg = createWidget(widget, frametitle)
          else # integer or string
            if Ops.get_boolean(ask, "password", false) == true
              widget1 = Password(
                Id(entry_id),
                Opt(:notify),
                question,
                Ops.get_string(ask, "default", "")
              )
              widget2 = Password(
                Id(:pass2), # FIXME: choose a better Id to avoid collisions
                Opt(:notify),
                "",
                Ops.get_string(ask, "default", "")
              )
              dlg = createWidget(
                VBox(MinWidth(40, widget1), MinWidth(40, widget2)),
                frametitle
              )
            else
              if Builtins.haskey(ask, "selection")
                dummy = []
                Builtins.foreach(s) do |e|
                  on = Ops.get_string(e, "value", "") == Ops.get(ask, "default") ? true : false
                  dummy = Builtins.add(
                    dummy,
                    Item(
                      Id(Ops.get_string(e, "value", "")),
                      Ops.get_string(e, "label", ""),
                      on
                    )
                  )
                end
                widget = ComboBox(Id(entry_id), Opt(:notify), question, dummy)
                dlg = createWidget(widget, frametitle)
              else
                widget = TextEntry(
                  Id(entry_id),
                  Opt(:notify),
                  question,
                  Ops.get_string(ask, "default", "")
                )
                dlg = createWidget(widget, frametitle)
              end
            end
          end
          #
          # At this time, widgets are created.
          #

          #
          # Add the widget to the correct frame (using the frametitle).
          #
          if frametitle != "" # some frametitle is set
            if frameBuffer == nil # and no frameBuffer exists
              frameBufferVBox = VBox(dlg) # create a new frameBuffer
            else # a frameBuffer exists
              if frametitle == frameBufferTitle # with same title
                frameBufferVBox = Builtins.add(frameBufferVBox, dlg) # add current to frameBuffer
              else # with different title
                dialog_term = Builtins.add(dialog_term, frameBuffer) # add frameBuffer to dialog
                dialog_term = Builtins.add(dialog_term, VSpacing(1))
                frameBufferVBox = VBox(dlg) # populate the frameBuffer with the new frame
              end
            end
            frameBuffer = Frame(frametitle, frameBufferVBox) # set frameBuffer values for the next iteration
            frameBufferTitle = frametitle
          else # frametitle is in blank
            if frameBuffer != nil # a previous frameBuffer exists
              dialog_term = Builtins.add(dialog_term, frameBuffer) # add frameBuffer to dialog
              dialog_term = Builtins.add(dialog_term, VSpacing(1))
              frameBuffer = nil
              frameBufferVBox = nil
            end
            dialog_term = Builtins.add(dialog_term, dlg) # add new element (with no frame) to dialog
            dialog_term = Builtins.add(dialog_term, VSpacing(1))
          end
        end

        # If some frameBuffer left after iterations, it's added to the dialog.
        if frameBuffer != nil
          dialog_term = Builtins.add(dialog_term, frameBuffer)
        end

        #
        # Let's build the dialog
        #
        help_term = HWeight(30, RichText(helptext)) if helptext != ""
        title_term = Heading(title) if title != ""
        backButton = PushButton(Id(:back), back_label)
        box = HBox(
          help_term,
          HSpacing(1),
          HWeight(
            70,
            VBox(
              title_term,
              VSpacing(1),
              VStretch(),
              dialog_term,
              VSpacing(1),
              VStretch(),
              HBox(HStretch(), backButton, PushButton(Id(:ok), ok_label))
            )
          ),
          HSpacing(1)
        )
        box = MinWidth(min_width, box) if Ops.greater_than(min_width, 0)
        box = MinHeight(min_height, box) if Ops.greater_than(min_height, 0)
        UI.OpenDialog(Opt(:decorated), box)
        if Ops.less_than(Builtins.size(history), 2)
          UI.ChangeWidget(Id(:back), :Enabled, false)
        end

        #
        # Wait for user input
        #
        while true
          ret = nil
          if timeout == 0
            ret = UI.UserInput
          else
            ret = UI.TimeoutUserInput(Ops.multiply(timeout, 1000))
          end
          timeout = 0
          if ret == :ok || ret == :timeout # Process users' input and save asks into dialogs hash.
            runAgain = 0
            element_cnt2 = 0
            Ops.set(
              dialogs,
              dialog_nr,
              Builtins.maplist( # Iterate through widgets building a list of asks (containing responses)
                Convert.convert(
                  Ops.get(dialogs, dialog_nr, []),
                  :from => "list",
                  :to   => "list <map>"
                )
              ) do |ask|
                file = Ops.get_string(ask, "file", "")
                script = Ops.get_map(ask, "script", {})
                entry_id = Builtins.sformat(
                  "%1_%2",
                  dialog_nr,
                  Ops.get_integer(ask, "element", element_cnt2)
                )
                element_cnt2 = Ops.add(element_cnt2, 1)
                val = UI.QueryWidget(Id(entry_id), :Value)
                if Ops.get_string(ask, "type", "string") == "integer"
                  val = Builtins.tointeger(Convert.to_string(val))
                end
                if Ops.get_boolean(ask, "password", false) == true
                  pass2 = Convert.to_string(UI.QueryWidget(Id(:pass2), :Value))
                  if pass2 != Convert.to_string(val)
                    Popup.Error("The two passwords mismatch.")
                    runAgain = 1 # Run the same dialog again.
                  end
                end
                Builtins.y2debug(
                  "question=%1 was answered with val=%2",
                  Ops.get_string(ask, "question", ""),
                  val
                )

                # Save the value in the profile (and also as default value)
                Ops.set(ask, "default", val)
                pos = path2pos(Ops.get_string(ask, "path", ""))
                if Ops.get_string(ask, "path", "") != "" # Set value in the profile
                  Profile.current = Profile.setElementByList(
                    pos,
                    val,
                    Profile.current
                  )
                end
                Builtins.foreach(Ops.get_list(ask, "pathlist", [])) do |p|
                  pos2 = path2pos(p)
                  Profile.current = Profile.setElementByList(
                    pos2,
                    val,
                    Profile.current
                  )
                end

                # Save the value into a file (if 'file' property was set)
                if file != ""
                  if Ops.get_string(ask, "type", "string") == "boolean"
                    if !SCR.Write(
                        path(".target.string"),
                        file,
                        Builtins.sformat(
                          "%1",
                          Convert.to_boolean(val) ? "true" : "false"
                        )
                      )
                      Builtins.y2milestone("writing answer to %1 failed", file)
                    end
                  else
                    if !SCR.Write(
                        path(".target.string"),
                        file,
                        Builtins.sformat("%1", val)
                      )
                      Builtins.y2milestone("writing answer to %1 failed", file)
                    end
                  end
                end

                # If ask must run an script, let's run it
                if script != {}
                  scriptName = Ops.get_string(
                    script,
                    "filename",
                    "ask_script.sh"
                  )
                  scriptPath = Builtins.sformat(
                    "%1/%2",
                    AutoinstConfig.tmpDir,
                    scriptName
                  )
                  SCR.Write(
                    path(".target.string"),
                    scriptPath,
                    Ops.get_string(script, "source", "echo 'no script'")
                  )
                  debug = Ops.get_boolean(script, "debug", true) ? "-x" : ""
                  current_logdir = AutoinstConfig.logs_dir
                  if Stage.initial
                    current_logdir = Builtins.sformat(
                      "%1/ask_scripts_log",
                      AutoinstConfig.tmpDir
                    )
                    SCR.Execute(path(".target.mkdir"), current_logdir)
                  end
                  executionString = ""
                  if Ops.get_boolean(script, "environment", false) # FIXME: why not pass the variable always?
                    if Ops.get_string(ask, "type", "string") == "boolean"
                      val = Builtins.sformat(
                        "%1",
                        Convert.to_boolean(val) ? "true" : "false"
                      )
                    end
                    executionString = Builtins.sformat(
                      "VAL=\"%5\" /bin/sh %1 %2 2&> %3/%4.log ",
                      debug,
                      scriptPath,
                      current_logdir,
                      scriptName,
                      AutoinstConfig.ShellEscape(Convert.to_string(val))
                    )
                  else
                    executionString = Builtins.sformat(
                      "/bin/sh %1 %2 2&> %3/%4.log ",
                      debug,
                      scriptPath,
                      current_logdir,
                      scriptName
                    )
                  end
                  if debug != ""
                    Builtins.y2milestone(
                      "Script Execution command: %1",
                      executionString
                    )
                  else
                    Builtins.y2debug(
                      "Script Execution command: %1",
                      executionString
                    )
                  end
                  Popup.Feedback("", _("A user defined script is running. This may take a while.")) do
                    runAgain = Ops.add(
                      runAgain,
                      Convert.to_integer(
                        SCR.Execute(path(".target.bash"), executionString)
                      )
                    )
                  end
                  if Ops.get_boolean(script, "rerun_on_error", false) == false
                    runAgain = 0
                  end

                  # Show feedback in a dialog
                  showFeedback = Ops.get_boolean(script, "feedback", false)
                  feedback = ""
                  if showFeedback
                    feedback = Convert.to_string(
                      SCR.Read(
                        path(".target.string"),
                        Ops.add(
                          Ops.add(Ops.add(current_logdir, "/"), scriptName),
                          ".log"
                        )
                      )
                    )
                  end
                  if Ops.greater_than(Builtins.size(feedback), 0)
                    Popup.LongText(
                      "",
                      RichText(Opt(:plainText), feedback),
                      70,
                      15
                    )
                  end

                  # Save the next_dialog
                  if Ops.greater_than(
                      SCR.Read(path(".target.size"), "/tmp/next_dialog"),
                      0
                    )
                    s = Convert.to_string(
                      SCR.Read(path(".target.string"), "/tmp/next_dialog")
                    )
                    s = Builtins.filterchars(s, "-0123456789")
                    jumpToDialog = Builtins.tointeger(s)
                    SCR.Execute(path(".target.remove"), "/tmp/next_dialog")
                    Builtins.y2milestone(
                      "next_dialog file found. Set dialog to %1",
                      jumpToDialog
                    )
                  end
                end
                deep_copy(ask)
              end
            )
            break if runAgain == 0
          elsif ret == :back # back button pressed: one step back on history.
            jumpToDialog = Ops.get(
              history,
              Ops.subtract(Builtins.size(history), 2),
              0
            )
            history = Builtins.remove(
              history,
              Ops.subtract(Builtins.size(history), 1)
            )
            history = Builtins.remove(
              history,
              Ops.subtract(Builtins.size(history), 1)
            )
            break
          end
        end
        UI.CloseDialog
        if jumpToDialog != -2 # If we must jump to another dialog (as read on /tmp/next_dialog)
          dialog_nr = jumpToDialog
          jumpToDialog = -2
          i = 0
          Builtins.foreach(keys) do |a|
            if a == dialog_nr
              dialogCounter = i
              raise Break
            end
            i = Ops.add(i, 1)
          end
        else # Next dialog
          dialogCounter = Ops.add(dialogCounter, 1)
          dialog_nr = Ops.get(keys, dialogCounter, -1)
        end
        Builtins.y2milestone("E dialog_nr = %1", dialog_nr)
        Builtins.y2milestone("E dialogCounter = %1", dialogCounter)
        Builtins.y2milestone("E jumpToDialog  %1", jumpToDialog)
      end
      mod
    end
  end
end
