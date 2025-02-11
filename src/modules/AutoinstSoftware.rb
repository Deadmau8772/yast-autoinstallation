# File:  modules/AutoinstSoftware.ycp
# Package:  Autoyast
# Summary:  Software
# Authors:  Anas Nashif <nashif@suse.de>
#
# $Id$
#
require "yast"
require "y2storage"
require "y2packager/product"
require "y2packager/resolvable"

module Yast
  class AutoinstSoftwareClass < Module
    include Yast::Logger

    # This file is created by pkg-bindings when the package solver fails,
    # it contains some details of the failure
    BAD_LIST_FILE = "/var/log/YaST2/badlist".freeze

    # Maximal amount of packages which will be shown
    # in a popup.
    MAX_PACKAGE_VIEW = 5

    def main
      Yast.import "UI"
      Yast.import "Pkg"
      textdomain "autoinst"

      Yast.import "Profile"
      Yast.import "Summary"
      Yast.import "Stage"
      Yast.import "SpaceCalculation"
      Yast.import "Packages"
      Yast.import "Popup"
      Yast.import "Report"
      Yast.import "Kernel"
      Yast.import "AutoinstConfig"
      Yast.import "AutoinstFunctions"
      Yast.import "ProductControl"
      Yast.import "Mode"
      Yast.import "Misc"
      Yast.import "Directory"
      Yast.import "Y2ModuleConfig"
      Yast.import "PackageSystem"
      Yast.import "ProductFeatures"
      Yast.import "WorkflowManager"

      Yast.include self, "autoinstall/io.rb"

      # All shared data are in yast2.rpm to break cyclic dependencies
      Yast.import "AutoinstData"

      Yast.import "PackageAI"

      @Software = {}

      @image = {}
      @image_arch = ""

      # patterns
      @patterns = []

      # Kernel, force type of kernel to be installed
      @kernel = ""

      # Packages that should be installed in continue mode
      # AutoinstData::post_packages = [];

      @ft_module = ""

      # Enable Imaging
      @imaging = false

      # default value of settings modified
      @modified = false

      @inst = []
      @all_xpatterns = []
      @packagesAvailable = []
      @patternsAvailable = []

      @instsource = ""
      @isolinuxcfg = ""
      AutoinstSoftware()
    end

    # Function sets internal variable, which indicates, that any
    # settings were modified, to "true"
    def SetModified
      @modified = true

      nil
    end

    # Functions which returns if the settings were modified
    # @return [Boolean]  settings were modified
    def GetModified
      @modified
    end

    # Import data
    # @param [Hash] settings settings to be imported
    # @return true on success
    def Import(settings)
      settings = deep_copy(settings)
      @Software = deep_copy(settings)
      @patterns = settings.fetch("patterns", [])
      @instsource = settings.fetch("instsource", "")

      @packagesAvailable = Pkg.GetPackages(:available, true)
      @patternsAvailable = Y2Packager::Resolvable.find(
        kind:         :pattern,
        user_visible: true
      ).map(&:name)

      regexFound = []
      Ops.set(
        settings,
        "packages",
        Builtins.filter(Ops.get_list(settings, "packages", [])) do |want_pack|
          next true if !Builtins.issubstring(want_pack, "/")

          want_pack = Builtins.deletechars(want_pack, "/")
          Builtins.foreach(@packagesAvailable) do |pack|
            Builtins.y2milestone("matching %1 against %2", pack, want_pack)
            if Builtins.regexpmatch(pack, want_pack)
              regexFound = Builtins.add(regexFound, pack)
              Builtins.y2milestone("match")
            end
          end
          false
        end
      )
      Ops.set(
        settings,
        "packages",
        Convert.convert(
          Builtins.union(Ops.get_list(settings, "packages", []), regexFound),
          from: "list",
          to:   "list <string>"
        )
      )

      regexFound = []
      @patterns = Builtins.filter(@patterns) do |want_patt|
        next true if !Builtins.issubstring(want_patt, "/")

        want_patt = Builtins.deletechars(want_patt, "/")
        Builtins.foreach(patternsAvailable) do |patt|
          Builtins.y2milestone("matching %1 against %2", patt, want_patt)
          if Builtins.regexpmatch(patt, want_patt)
            regexFound = Builtins.add(regexFound, patt)
            Builtins.y2milestone("match")
          end
        end
        false
      end
      @patterns = Convert.convert(
        Builtins.union(@patterns, regexFound),
        from: "list",
        to:   "list <string>"
      )

      PackageAI.toinstall = settings.fetch("packages", [])
      @kernel = settings.fetch("kernel", "")

      addPostPackages(settings.fetch("post-packages", []))
      AutoinstData.post_patterns = settings.fetch("post-patterns", [])
      PackageAI.toremove = settings.fetch("remove-packages", [])

      # Imaging
      # map<string, any> image = settings["system_images"]:$[];
      # imaging = image["enable_multicast_images"]:false;
      # ft_module = image["module_name"]:"";
      # if (settings == $[])
      #     modified = false;
      # else
      #     modified = true;
      @image = settings.fetch("image", {})

      # image_location and image_name are not mandatory for
      # extracting an image because it can be defined in the
      # script too. So it will not be checked here.
      @imaging = true if @image["script_location"] && !@image["script_location"].empty?
      true
    end

    def AddYdepsFromProfile(entries)
      Builtins.y2milestone("AddYdepsFromProfile entries %1", entries)
      pkglist = []
      entries.each do |e|
        yast_module, _entry = Y2ModuleConfig.ModuleMap.find do |module_name, entry|
          module_name == e ||
            entry["X-SuSE-YaST-AutoInstResource"] == e ||
            (entry["X-SuSE-YaST-AutoInstMerge"]&.split(",")&.include?(e))
        end
        # if needed taking default because no entry has been defined in the *.desktop file
        yast_module ||= e
        # FIXME: Does not work see below
        #
        # This does currently not work at all as the packages provide this
        # with the module name camel-cased; e.g.:
        #
        #   application(YaST2/org.opensuse.yast.Kdump.desktop)
        #
        # As there's no way to predict which letters are upper-cased this cannot work at all.
        #
        # The fallback method via #required_packages relies on a
        # pre-calculated data set which may or may not reflect the
        # dependencies of the packages in the repo.
        #
        # This area should be re-thought entirely.
        #
        provide = "application(YaST2/org.opensuse.yast.#{yast_module}.desktop)"

        packages = Pkg.PkgQueryProvides(provide)
        if packages.empty?
          packs = Y2ModuleConfig.required_packages([e])[e]
          if packs.nil? || packs.empty?
            log.info "No package provides: #{provide}"
          else
            log.info "AddYdepsFromProfile add packages #{packs} for entry #{e}"
            pkglist += packs
          end
        else
          name = packages[0][0]
          log.info "AddYdepsFromProfile add package #{name} for entry #{e}"
          pkglist.push(name) if !pkglist.include?(name)
        end
      end
      pkglist.uniq!
      Builtins.y2milestone("AddYdepsFromProfile pkglist %1", pkglist)
      pkglist.each do |p|
        if !PackageAI.toinstall.include?(p) && @packagesAvailable.include?(p)
          PackageAI.toinstall.push(p)
        end
      end
    end

    # Constructer
    def AutoinstSoftware
      if Stage.cont && Mode.autoinst
        Pkg.TargetInit("/", false)
        Import(Ops.get_map(Profile.current, "software", {}))
      end
      nil
    end

    def GetArchOfELF(filename)
      bash_out = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Ops.add(Ops.add(Directory.ybindir, "/elf-arch "), filename)
        )
      )
      return "unknown" if Ops.get_integer(bash_out, "exit", 1) != 0

      Builtins.deletechars(Ops.get_string(bash_out, "stdout", "unknown"), "\n")
    end

    def createImage(targetdir)
      rootdir = Convert.to_string(SCR.Read(path(".target.tmpdir")))
      zypperCall = ""
      outputRedirect = " 2>&1 >> /tmp/ay_image.log"
      finalPopup = Builtins.size(targetdir) == 0
      Ops.set(
        @image,
        "script_location",
        Ops.get_string(
          @image,
          "script_location",
          "file:///usr/lib/YaST2/bin//fetch_image.sh"
        )
      )
      Ops.set(
        @image,
        "script_params",
        Convert.convert(
          Ops.get(@image, "script_params") do
            [
              Ops.add(
                Ops.add(
                  Ops.add(Ops.get_string(@image, "image_location", ""), "/"),
                  Ops.get_string(@image, "image_name", "image")
                ),
                ".tar.gz"
              )
            ]
          end,
          from: "any",
          to:   "list <string>"
        )
      )

      SCR.Execute(path(".target.bash"), "rm -f /tmp/ay_image.log")

      # bind-mount devices
      SCR.Execute(path(".target.mkdir"), Ops.add(rootdir, "/dev"))
      returnCode = Convert.to_integer(
        SCR.Execute(
          path(".target.bash"),
          Builtins.sformat("touch /%1/dev/null %1/dev/zero", rootdir)
        )
      )
      returnCode = Convert.to_integer(
        SCR.Execute(
          path(".target.bash"),
          Builtins.sformat("mount -o bind /dev/zero /%1/dev/zero", rootdir)
        )
      )
      returnCode = Convert.to_integer(
        SCR.Execute(
          path(".target.bash"),
          Builtins.sformat("mount -o bind /dev/null /%1/dev/null", rootdir)
        )
      )

      # Add Source:
      # zypper --root /space/tmp/tmproot/ ar \
      #   ftp://10.10.0.100/install/SLP/openSUSE-11.2/i386/DVD1/ main
      zypperCall = Builtins.sformat(
        "ZYPP_READONLY_HACK=1 zypper --root %1 --gpg-auto-import-keys " \
          "--non-interactive ar %2 main-source %3",
        rootdir,
        @instsource,
        outputRedirect
      )
      Builtins.y2milestone("running %1", zypperCall)
      returnCode = Convert.to_integer(
        SCR.Execute(path(".target.bash"), zypperCall)
      )
      if returnCode != 0 && returnCode != 4
        # 4 means "already exists"
        Popup.Error(Builtins.sformat(_("Adding repo %1 failed"), @instsource))
      end

      # Add add-ons
      addOnExport = Convert.to_map(WFM.CallFunction("add-on_auto", ["Export"]))
      addOns = Ops.get_list(addOnExport, "add_on_products", [])
      Builtins.foreach(addOns) do |addOn|
        zypperCall = Builtins.sformat(
          "ZYPP_READONLY_HACK=1 zypper --root %1 --gpg-auto-import-keys " \
            "--non-interactive ar %2 %3 %4",
          rootdir,
          Ops.get_string(addOn, "media_url", ""),
          Ops.get_string(addOn, "product", ""),
          outputRedirect
        )
        returnCode = Convert.to_integer(
          SCR.Execute(path(".target.bash"), zypperCall)
        )
        if returnCode != 0 && returnCode != 4
          Popup.Error(
            Builtins.sformat(
              _("Adding repo %1 failed"),
              Ops.get_string(addOn, "product", "")
            )
          )
        end
      end

      # Install
      zypperCall = Builtins.sformat(
        "ZYPP_READONLY_HACK=1 zypper --root %1 --gpg-auto-import-keys " \
          "--non-interactive install --auto-agree-with-licenses ",
        rootdir
      )

      pattern = Builtins.mergestring(@patterns, " ")
      Popup.ShowFeedback("Creating Image - installing patterns", "")
      Builtins.y2milestone("installing %1", pattern)
      returnCode = Convert.to_integer(
        SCR.Execute(
          path(".target.bash"),
          Ops.add(
            Ops.add(Ops.add(zypperCall, "-t pattern "), pattern),
            outputRedirect
          )
        )
      )
      Popup.ClearFeedback
      if returnCode != 0
        Popup.Error(
          _(
            "Image creation failed while pattern installation. Please check /tmp/ay_image.log"
          )
        )
      end

      if Ops.greater_than(Builtins.size(PackageAI.toinstall), 0)
        package = Builtins.mergestring(PackageAI.toinstall, " ")
        Popup.ShowFeedback(_("Creating Image - installing packages"), "")
        returnCode = Convert.to_integer(
          SCR.Execute(
            path(".target.bash"),
            Ops.add(Ops.add(Ops.add(zypperCall, " "), package), outputRedirect)
          )
        )
        Popup.ClearFeedback
        if returnCode != 0
          Popup.Error(
            _(
              "Image creation failed while package installation. Please check /tmp/ay_image.log"
            )
          )
        end
      end

      @image_arch = GetArchOfELF(Builtins.sformat("%1/bin/bash", rootdir))
      Builtins.y2milestone("Image architecture = %1", @image_arch)
      targetdir = UI.AskForExistingDirectory("/", _("Store image to ...")) if targetdir == ""

      # umount devices
      returnCode = Convert.to_integer(
        SCR.Execute(
          path(".target.bash"),
          Builtins.sformat("umount %1/dev/null %1/dev/zero %1/proc", rootdir)
        )
      )
      returnCode = Convert.to_integer(
        SCR.Execute(
          path(".target.bash"),
          Builtins.sformat("rm -rf %1/dev", rootdir)
        )
      )

      # Compress image:
      # tar cfz /srv/www/htdocs/image.tar.gz --exclude="proc*"  .
      tarCommand = Builtins.sformat(
        "tar cfvz %4/%3.tar.gz --exclude=\"./proc*\" --exclude=\"/%3.tar.gz\" -C %1 . %2",
        rootdir,
        outputRedirect,
        Ops.get_string(@image, "image_name", ""),
        targetdir
      )
      Builtins.y2milestone("running %1", tarCommand)
      Popup.Message(
        Builtins.sformat(
          _(
            "You can do changes to the image now in %1/\n" \
              "If you press the ok-button, the image will be compressed and " \
              "can't be changed anymore."
          ),
          rootdir
        )
      )
      Popup.ShowFeedback("Compressing Image ...", "")
      returnCode = Convert.to_integer(
        SCR.Execute(path(".target.bash"), tarCommand)
      )
      Popup.ClearFeedback
      if returnCode != 0
        Popup.Error(
          Builtins.sformat(
            _(
              "Image compressing failed in '%1'. Please check /tmp/ay_image.log"
            ),
            rootdir
          )
        )
      end
      Popup.Message(_("Image created successfully")) if finalPopup

      nil
    end

    def copyFiles4ISO(target)
      ret = true
      copy = Misc.SysconfigRead(
        path(".sysconfig.autoinstall.COPY_FOR_ISO"),
        "/,/boot/,/boot/__ARCH__/,/boot/__ARCH__/loader/,/media.1/,/suse/setup/descr/"
      )
      copyList = Builtins.splitstring(copy, ",")

      Builtins.foreach(copyList) do |source|
        if Builtins.issubstring(source, "__ARCH__")
          source = Builtins.regexpsub(
            source,
            "(.*)__ARCH__(.*)",
            Builtins.sformat("\\1%1\\2", @image_arch)
          )
        end
        if Builtins.substring(source, Ops.subtract(Builtins.size(source), 1)) == "/"
          # copy a directory (ends with / in directory.yast)
          SCR.Execute(
            path(".target.mkdir"),
            Ops.add(Ops.add(target, "/"), source)
          )
          if !GetURL(
            Ops.add(
              Ops.add(Ops.add(@instsource, "/"), source),
              "directory.yast"
            ),
            "/tmp/directory.yast"
          )
            Popup.Error(
              Builtins.sformat(
                _(
                  "can not get the directory.yast file at `%1`.\n" \
                    "You can create that file with 'ls -F > directory.yast' if it's missing."
                ),
                Ops.add(Ops.add(@instsource, "/"), source)
              )
            )
            ret = false
            raise Break
          end
          # directory.yast is our filelist
          files = Convert.to_string(
            SCR.Read(path(".target.string"), "/tmp/directory.yast")
          )
          filesInDir = Builtins.splitstring(files, "\n")
          Builtins.foreach(filesInDir) do |file|
            # don't copy subdirs. They have to be mentioned explicit. Copy only files from that dir.
            Builtins.y2milestone(
              "will get %1 from %2 to %3",
              file,
              Ops.add(Ops.add(@instsource, "/"), source),
              target
            )
            if Ops.greater_than(Builtins.size(file), 0) &&
                Builtins.substring(file, Ops.subtract(Builtins.size(file), 1)) != "/"
              while ret &&
                  !GetURL(
                    Ops.add(Ops.add(Ops.add(@instsource, "/"), source), file),
                    Ops.add(
                      Ops.add(Ops.add(Ops.add(target, "/"), source), "/"),
                      file
                    )
                  )
                next if Popup.YesNo(
                  Builtins.sformat(
                    _("can not read '%1'. Try again?"),
                    Ops.add(Ops.add(Ops.add(@instsource, "/"), source), file)
                  )
                )

                ret = false
              end
            end
            raise Break if !ret
          end
        # copy a file
        elsif !GetURL(
          Ops.add(Ops.add(@instsource, "/"), source),
          Ops.add(Ops.add(target, "/"), source)
        )
          Popup.Error(
            Builtins.sformat(
              _("can not read '%1'. ISO creation failed"),
              Ops.add(Ops.add(@instsource, "/"), source)
            )
          )
          ret = false
          raise Break
        end
      end
      # lets always copy an optional(!) driverupdate file.
      # It's very unlikely that it's in directory.yast
      GetURL(
        Ops.add(@instsource, "/driverupdate"),
        Ops.add(target, "/driverupdate")
      )
      SCR.Execute(
        path(".target.bash"),
        Builtins.sformat("cp /usr/lib/YaST2/bin/fetch_image.sh %1/", target)
      )
      ret
    end

    def createISO
      # we will have the image.tar.gz and autoinst.xml on the root of the DVD/CD
      isodir = "/tmp/ay_iso/"
      SCR.Execute(path(".target.bash"), Builtins.sformat("rm -rf %1", isodir))
      SCR.Execute(path(".target.mkdir"), isodir)
      outputRedirect = " 2>&1 >> /tmp/ay_image.log"
      createImage(isodir)

      Popup.ShowFeedback(_("Preparing ISO Filestructure ..."), "")
      copyFiles4ISO(isodir)
      Popup.ClearFeedback

      # prepare and save autoinst.xml
      Ops.set(@image, "image_location", "file:///")
      Ops.set(
        @image,
        "script_params",
        [
          Ops.add(
            Ops.add(
              Ops.add(Ops.get_string(@image, "image_location", ""), "/"),
              Ops.get_string(@image, "image_name", "")
            ),
            ".tar.gz"
          )
        ]
      )
      Ops.set(@image, "script_location", "file:///fetch_image.sh")
      Profile.Save(Builtins.sformat("%1/autoinst.xml", isodir))

      # prepare and save isolinux.cfg boot menu of the media
      @isolinuxcfg = Convert.to_string(
        SCR.Read(
          path(".target.string"),
          Builtins.sformat(
            "%1/boot/%2/loader/isolinux.cfg",
            isodir,
            @image_arch
          )
        )
      )
      lines = Builtins.splitstring(@isolinuxcfg, "\n")
      lines = Builtins.maplist(lines) do |l|
        l = Ops.add(l, " autoyast=file:///autoinst.xml") if Builtins.issubstring(l, " append ")
        l
      end
      @isolinuxcfg = Builtins.mergestring(lines, "\n")

      UI.OpenDialog(
        Opt(:decorated),
        VBox(
          HBox(
            VSpacing(14),
            MultiLineEdit(
              Id(:isolinuxcfg),
              _("boot config for the DVD"),
              @isolinuxcfg
            )
          ),
          PushButton(Id(:create_image), Opt(:default, :hstretch), _("Ok")),
          Label(
            Builtins.sformat(
              _(
                "You can do changes to the ISO now in %1, like adding a " \
                  "complete different AutoYaST XML file.\n" \
                  "If you press the ok-button, the iso will be created."
              ),
              isodir
            )
          )
        )
      )
      UI.UserInput
      @isolinuxcfg = Convert.to_string(UI.QueryWidget(:isolinuxcfg, :Value))
      UI.CloseDialog
      SCR.Write(
        path(".target.string"),
        Builtins.sformat("%1/boot/%2/loader/isolinux.cfg", isodir, @image_arch),
        @isolinuxcfg
      )

      # create the actual ISO file
      targetdir = UI.AskForExistingDirectory("/", _("Store ISO image to ..."))
      Popup.ShowFeedback(_("Creating ISO File ..."), "")
      cmd = Builtins.sformat(
        "mkisofs -o %1/%2.iso -R -b boot/%3/loader/isolinux.bin -c boot.cat " \
          "-no-emul-boot -boot-load-size 4 -boot-info-table %4",
        targetdir,
        Ops.get_string(@image, "image_name", ""),
        @image_arch,
        isodir
      )
      Builtins.y2milestone("executing %1", Ops.add(cmd, outputRedirect))
      returnCode = Convert.to_integer(SCR.Execute(path(".target.bash"), cmd))
      Popup.ClearFeedback
      if returnCode != 0
        Popup.Error(
          Builtins.sformat(
            "ISO creation failed in '%1'. Please check /tmp/ay_image.log",
            isodir
          )
        )
      else
        Popup.Message(
          Builtins.sformat(
            _("ISO successfully created at %1"),
            Ops.add(
              Ops.add("/tmp/", Ops.get_string(@image, "image_name", "")),
              ".iso"
            )
          )
        )
      end

      nil
    end

    # Export data
    # @return dumped settings (later acceptable by Import())
    def Export
      s = {}
      s["kernel"] = @kernel if !@kernel.empty?
      s["patterns"] = @patterns if !@patterns.empty?

      pkg_toinstall = PackageAI.toinstall
      s["packages"] = pkg_toinstall if !pkg_toinstall.empty?

      pkg_post = AutoinstData.post_packages
      s["post-packages"] = pkg_post if !pkg_post.empty?

      pkg_toremove = PackageAI.toremove
      s["remove-packages"] = PackageAI.toremove if !pkg_toremove.empty?

      s["instsource"] = @instsource
      s["image"] = @image

      # In the installed system the flag solver.onlyRequires in zypp.conf is
      # set to true. This differs from the installation process. So we have
      # to set "install_recommended" to true in order to reflect the
      # installation process and cannot use the package bindings. (bnc#990494)
      # OR: Each product (e.g. CASP) can set it in the control.xml file.
      rec = ProductFeatures.GetStringFeature(
        "software",
        "clone_install_recommended_default"
      )
      s["install_recommended"] = rec != "no"

      products = Product.FindBaseProducts
      raise "Found multiple base products" if products.size > 1

      s["products"] = products.map { |x| x["name"] }

      s
    end

    # Add packages needed by modules, i.e. NIS, NFS etc.
    # @param module_packages [Array<String>] list of strings packages to add
    def AddModulePackages(module_packages)
      module_packages = deep_copy(module_packages)
      PackageAI.toinstall = Builtins.toset(
        Convert.convert(
          Builtins.union(PackageAI.toinstall, module_packages),
          from: "list",
          to:   "list <string>"
        )
      )
      #
      # Update profile
      #
      Ops.set(Profile.current, "software", Export())
      nil
    end

    # Remove packages not needed by modules, i.e. NIS, NFS etc.
    # @param module_packages [Array<String>] list of strings packages to add
    def RemoveModulePackages(module_packages)
      module_packages = deep_copy(module_packages)
      PackageAI.toinstall = Builtins.filter(PackageAI.toinstall) do |p|
        !Builtins.contains(module_packages, p)
      end
      Ops.set(Profile.current, "software", Export())
      nil
    end

    # Summary
    # @return Html formatted configuration summary
    def Summary
      summary = ""

      summary = Summary.AddHeader(summary, _("Selected Patterns"))
      if Ops.greater_than(Builtins.size(@patterns), 0)
        summary = Summary.OpenList(summary)
        Builtins.foreach(@patterns) do |a|
          summary = Summary.AddListItem(summary, a)
        end
        summary = Summary.CloseList(summary)
      else
        summary = Summary.AddLine(summary, Summary.NotConfigured)
      end
      summary = Summary.AddHeader(summary, _("Individually Selected Packages"))
      summary = Summary.AddLine(
        summary,
        Builtins.sformat("%1", Builtins.size(PackageAI.toinstall))
      )

      summary = Summary.AddHeader(summary, _("Packages to Remove"))
      summary = Summary.AddLine(
        summary,
        Builtins.sformat("%1", Builtins.size(PackageAI.toremove))
      )

      if @kernel != ""
        summary = Summary.AddHeader(summary, _("Force Kernel Package"))
        summary = Summary.AddLine(summary, Builtins.sformat("%1", @kernel))
      end
      summary
    end

    # Compute list of packages selected by user and other packages needed for important
    # configuration modules.
    # @return [Array] of strings list of packages needed for autoinstallation
    def autoinstPackages
      allpackages = []

      # the primary list of packages
      allpackages = Convert.convert(
        Builtins.union(allpackages, PackageAI.toinstall),
        from: "list",
        to:   "list <string>"
      )

      # In autoinst mode, a kernel should not be  available
      # in <packages>
      if Builtins.size(@kernel) == 0
        kernel_pkgs = Kernel.ComputePackages
        allpackages = Convert.convert(
          Builtins.union(allpackages, kernel_pkgs),
          from: "list",
          to:   "list <string>"
        )
      elsif Pkg.IsAvailable(@kernel)
        allpackages = Builtins.add(allpackages, @kernel)
        kernel_nongpl = Ops.add(@kernel, "-nongpl")

        allpackages = Builtins.add(allpackages, kernel_nongpl) if Pkg.IsAvailable(kernel_nongpl)
      else
        Builtins.y2warning("%1 not available, using kernel-default", @kernel)
        kernel_pkgs = Kernel.ComputePackages
        allpackages = Convert.convert(
          Builtins.union(allpackages, kernel_pkgs),
          from: "list",
          to:   "list <string>"
        )
      end

      deep_copy(allpackages)
    end

    # Configure software settings
    #
    # @return [Boolean]
    def Write
      if @imaging
        ProductControl.DisableModule("kickoff") if !Ops.get_boolean(@image, "run_kickoff", false)
        ProductControl.DisableModule("rpmcopy")
        return true
      end

      ok = true

      Packages.Init(true)
      # Resetting package selection of previous runs. This is needed
      # because it could be that additional repositories
      # are available meanwhile. (bnc#979691)
      Pkg.PkgApplReset

      sw_settings = Profile.current.fetch("software", {})
      Pkg.SetSolverFlags(
        "ignoreAlreadyRecommended" => Mode.normal,
        "onlyRequires"             => !sw_settings.fetch("install_recommended", true)
      )

      failed = []

      # Add storage-related software packages (filesystem tools etc.) to the
      # set of packages to be installed.
      pkg_handler = Y2Storage::PackageHandler.new
      pkg_handler.add_feature_packages(Y2Storage::StorageManager.instance.staging)
      pkg_handler.set_proposal_packages

      # switch for recommended patterns installation (workaround for our very weird pattern design)
      if sw_settings.fetch("install_recommended", false) == false
        # set SoftLock to avoid the installation of recommended patterns (#159466)
        Y2Packager::Resolvable.find(kind: :pattern).each do |p|
          Pkg.ResolvableSetSoftLock(p.name, :pattern)
        end
      end

      Builtins.foreach(Builtins.toset(@patterns)) do |p|
        failed = Builtins.add(failed, p) if !Pkg.ResolvableInstall(p, :pattern)
      end

      if Ops.greater_than(Builtins.size(failed), 0)
        Builtins.y2error(
          "Error while setting pattern: %1",
          Builtins.mergestring(failed, ",")
        )
        Report.Warning(
          Builtins.sformat(
            _("Could not set patterns: %1."),
            Builtins.mergestring(failed, ",")
          )
        )
      end

      selected_product = AutoinstFunctions.selected_product
      if selected_product
        log.info "Selecting product #{selected_product.inspect} for installation"
        selected_product.select
      else
        log.info "No product has been selected for installation"
      end

      SelectPackagesForInstallation()

      computed_packages = Packages.ComputeSystemPackageList
      Builtins.foreach(computed_packages) do |pack2|
        if Ops.greater_than(Builtins.size(@kernel), 0) && pack2 != @kernel &&
            Builtins.search(pack2, "kernel-") == 0
          Builtins.y2milestone("taboo for kernel %1", pack2)
          PackageAI.toremove = Builtins.add(PackageAI.toremove, pack2)
        end
      end

      #
      # Now remove all packages listed in remove-packages
      #
      Builtins.y2milestone("Packages to be removed: %1", PackageAI.toremove)
      if Ops.greater_than(Builtins.size(PackageAI.toremove), 0)
        Builtins.foreach(PackageAI.toremove) do |rp|
          # Pkg::ResolvableSetSoftLock( rp, `package ); // FIXME: maybe better Pkg::PkgTaboo(rp) ?
          Pkg.PkgTaboo(rp)
        end

        Pkg.DoRemove(PackageAI.toremove)
      end

      #
      # Solve dependencies
      #
      if !Pkg.PkgSolve(false)
        # TRANSLATORS: Error message
        msg = _("The package resolver run failed. Please check your software " \
          "section in the autoyast profile.")
        # TRANSLATORS: Error message, %s is replaced by "/var/log/YaST2/y2log"
        msg += "\n" + _("Additional details can be found in the %s file.") %
          "/var/log/YaST2/y2log"

        # read the details saved by pkg-bindings
        if File.exist?(BAD_LIST_FILE)
          msg += "\n\n"
          msg += File.read(BAD_LIST_FILE)
        end

        Report.LongError(msg)
      end

      SpaceCalculation.ShowPartitionWarning

      ok
    end

    # Initialize temporary target
    def pmInit
      #        string tmproot = AutoinstConfig::tmpDir;

      #        SCR::Execute(.target.mkdir, tmproot + "/root");
      #        Pkg::TargetInit( tmproot + "/root", true);
      #        Pkg::TargetInit( "/", true);
      Pkg.TargetInit(Convert.to_string(SCR.Read(path(".target.tmpdir"))), true)
      Builtins.y2milestone("SourceStartCache: %1", Pkg.SourceStartCache(false))
      nil
    end

    # Add post packages
    # @param calcpost [Array<String>] list calculated post packages
    def addPostPackages(calcpost)
      # filter out already installed packages
      calcpost.reject! { |p| PackageSystem.Installed(p) }

      calcpost = deep_copy(calcpost)
      AutoinstData.post_packages = Convert.convert(
        Builtins.toset(Builtins.union(calcpost, AutoinstData.post_packages)),
        from: "list",
        to:   "list <string>"
      )
      nil
    end

    # returns (hard and soft) locked packages
    # @return [Array<String>] list of package names
    def locked_packages
      # hard AND soft locks
      user_transact_packages(:taboo).concat(user_transact_packages(:available))
    end

    def install_packages
      # user selected packages which have not been already installed
      # rubocop:disable Lint/UselessAssignment
      packages = Pkg.FilterPackages(
        solver_selected = false,
        app_selected = true,
        user_selected = true,
        name_only = true
      )
      # rubocop:enable Lint/UselessAssignment

      # user selected packages which have already been installed
      installed_by_user = Pkg.GetPackages(:installed, true).select do |pkg_name|
        Pkg.PkgPropertiesAll(pkg_name).any? do |p|
          p["on_system_by_user"] && p["status"] == :installed
        end
      end

      # Filter out kernel and pattern packages
      kernel_packages = Pkg.PkgQueryProvides("kernel").collect do |package|
        package[0]
      end.compact.uniq
      pattern_packages = Pkg.PkgQueryProvides("pattern()").collect do |package|
        package[0]
      end.compact.uniq

      (packages + installed_by_user).uniq.select do |pkg_name|
        !kernel_packages.include?(pkg_name) &&
          !pattern_packages.include?(pkg_name)
      end
    end

    # Return list of software packages of calling client
    # in the installed environment
    # @return [Hash] map of installed software package
    #    "patterns" -> list<string> addon selections
    #    "packages" -> list<string> user selected packages
    #      "remove-packages" -> list<string> packages to remove
    def ReadHelper
      Pkg.TargetInit("/", false)
      Pkg.TargetLoad
      Pkg.SourceStartManager(true)
      Pkg.PkgSolve(false)

      @all_xpatterns = Y2Packager::Resolvable.find(kind: :pattern)
      to_install_packages = install_packages
      patterns = []

      @all_xpatterns.each do |p|
        if p.status == :installed &&
            !patterns.include?(p.name)
          (patterns << p.name.empty?) ? "no name" : p.name
        end
      end
      Pkg.TargetFinish

      tmproot = AutoinstConfig.tmpDir
      SCR.Execute(path(".target.mkdir"), Ops.add(tmproot, "/rootclone"))
      Pkg.TargetInit(Ops.add(tmproot, "/rootclone"), true)
      Builtins.y2debug("SourceStartCache: %1", Pkg.SourceStartCache(false))

      Pkg.SourceStartManager(true)
      Pkg.TargetFinish

      new_p = []
      Builtins.foreach(patterns) do |tmp_pattern|
        xpattern = Builtins.filter(@all_xpatterns) do |p|
          p.name == tmp_pattern
        end
        found = Ops.get(xpattern, 0, {})
        req = false
        # kick out hollow patterns (always fullfilled patterns)
        Builtins.foreach(Ops.get_list(found, "dependencies", [])) do |d|
          if Ops.get_string(d, "res_kind", "") == "package" &&
              (Ops.get_string(d, "dep_kind", "") == "requires" ||
                Ops.get_string(d, "dep_kind", "") == "recommends")
            req = true
          end
        end
        # workaround for our pattern design
        # a pattern with no requires at all is always fullfilled of course
        # you can fullfill the games pattern with no games installed at all
        new_p = Builtins.add(new_p, tmp_pattern) if req == true
      end
      patterns = deep_copy(new_p)

      software = {}

      Ops.set(software, "patterns", Builtins.sort(patterns))
      # Currently we do not have any information about user deleted packages in
      # the installed system.
      # In order to prevent a reinstallation we can take the locked packages at least.
      # (bnc#888296)
      software["remove-packages"] = locked_packages

      software["packages"] = to_install_packages

      deep_copy(software)
    end

    # Return list of software packages, patterns which have been selected
    # by the user and have to be installed or removed.
    # The evaluation will be called while the yast installation workflow.
    # @return [Hash] map of to be installed/removed packages/patterns
    #    "patterns" -> list<string> of selected patterns
    #    "packages" -> list<string> user selected packages
    #           "remove-packages" -> list<string> packages to remove
    def read_initial_stage
      install_patterns =
        Y2Packager::Resolvable.find(kind: :pattern, user_visible: true).map do |pattern|
          # Do not take care about if the pattern has been selected by the user or the product
          # definition, cause we need a base selection here for the future
          # autoyast installation. (bnc#882886)
          pattern.name if pattern.status == :selected || pattern.status == :installed
        end

      software = {}
      software["packages"] = install_packages
      software["patterns"] = install_patterns.compact
      software["remove-packages"] = locked_packages
      Builtins.y2milestone("autoyast software selection: %1", software)
      deep_copy(software)
    end

    def Read
      Import((Stage.initial ? read_initial_stage : ReadHelper()))
    end

    def SavePackageSelection
      @saved_package_selection = Read()
    end

    def SavedPackageSelection
      @saved_package_selection
    end

    # Selects given product (see Y2Packager::Product) and merges its workflow
    def merge_product(product)
      raise ArgumentError, "Base product expected" if !product

      log.info("AutoinstSoftware::merge_product - using product: #{product.name}")
      product.select

      WorkflowManager.merge_product_workflow(product)

      # Adding needed autoyast packages if a second stage is needed.
      # Could have been changed due merging a products
      log.info("Checking new second stage requirement.")
      Profile.softwareCompat
    end

    def SelectPackagesForInstallation
      log.info "Individual Packages for installation: #{autoinstPackages}"
      failed_packages = {}
      failed_packages = Pkg.DoProvide(autoinstPackages) unless autoinstPackages.empty?
      computed_packages = Packages.ComputeSystemPackageList
      log.info "Computed packages for installation: #{computed_packages}"
      if !computed_packages.empty?
        failed_packages = failed_packages.merge(Pkg.DoProvide(computed_packages))
      end

      # Blaming only packages which have been selected by the AutoYaST configuration file
      log.error "Cannot select following packages for installation:" unless failed_packages.empty?
      failed_packages.reject! do |name, reason|
        if @Software["packages"]&.include?(name)
          log.error("  #{name} : #{reason} (selected by AutoYaST configuration file)")
          false
        else
          log.error("  #{name} : #{reason} (selected by YAST automatically)")
          true
        end
      end

      unless failed_packages.empty?
        not_selected = ""
        suggest_y2log = false
        failed_count = failed_packages.size
        if failed_packages.size > MAX_PACKAGE_VIEW
          failed_packages = failed_packages.first(MAX_PACKAGE_VIEW).to_h
          suggest_y2log = true
        end
        failed_packages.each do |name, reason|
          not_selected << "#{name}: #{reason}\n"
        end
        # TRANSLATORS: Warning text during the installation. %s is a list of package
        error_message = _("These packages cannot be found in the software repositories:\n%s") %
          not_selected
        if suggest_y2log
          # TRANSLATORS: Error message, %d is replaced by the amount of failed packages.
          error_message += _("and %d additional packages") % (failed_count - MAX_PACKAGE_VIEW)
          # TRANSLATORS: Error message, %s is replaced by "/var/log/YaST2/y2log"
          error_message += "\n\n" + _("Details can be found in the %s file.") %
            "/var/log/YaST2/y2log"
        end

        Report.Error(error_message)
      end
    end

    publish function: :merge_product, type: "void (string)"
    publish variable: :Software, type: "map"
    publish variable: :image, type: "map <string, any>"
    publish variable: :image_arch, type: "string"
    publish variable: :patterns, type: "list <string>"
    publish variable: :kernel, type: "string"
    publish variable: :ft_module, type: "string"
    publish variable: :imaging, type: "boolean"
    publish variable: :modified, type: "boolean"
    publish variable: :inst, type: "list <string>"
    publish variable: :all_xpatterns, type: "list <map <string, any>>"
    publish variable: :instsource, type: "string"
    publish variable: :isolinuxcfg, type: "string"
    publish function: :SetModified, type: "void ()"
    publish function: :GetModified, type: "boolean ()"
    publish function: :Import, type: "boolean (map)"
    publish function: :AutoinstSoftware, type: "void ()"
    publish function: :createImage, type: "void (string)"
    publish function: :copyFiles4ISO, type: "boolean (string)"
    publish function: :createISO, type: "void ()"
    publish function: :Export, type: "map ()"
    publish function: :AddModulePackages, type: "void (list <string>)"
    publish function: :AddYdepsFromProfile, type: "void (list <string>)"
    publish function: :RemoveModulePackages, type: "void (list <string>)"
    publish function: :Summary, type: "string ()"
    publish function: :autoinstPackages, type: "list <string> ()"
    publish function: :Write, type: "boolean ()"
    publish function: :pmInit, type: "void ()"
    publish function: :addPostPackages, type: "void (list <string>)"
    publish function: :ReadHelper, type: "map <string, any> ()"
    publish function: :Read, type: "boolean ()"

  private

    # Get user transacted packages, include only the packages in the requested state
    # @param status [Symbol] package status (:available, :selected, :installed,
    # :removed)
    # @return [Array<String>] package names
    def user_transact_packages(status)
      # only package names (without version)
      names_only = true
      packages = Pkg.GetPackages(status, names_only)

      # iterate over each package, Pkg.ResolvableProperties("", :package, "") requires a lot of
      # memory
      packages.select do |package|
        Pkg.PkgPropertiesAll(package).any? do |p|
          p["transact_by"] == :user && p["status"] == status
        end
      end
    end
  end

  AutoinstSoftware = AutoinstSoftwareClass.new
  AutoinstSoftware.main
end
