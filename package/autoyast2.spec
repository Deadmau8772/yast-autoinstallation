#
# spec file for package autoyast2
#
# Copyright (c) 2013 SUSE LINUX Products GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.

# Please submit bugfixes or comments via https://bugs.opensuse.org/
#


#Compat macro for new _fillupdir macro introduced in Nov 2017
%if ! %{defined _fillupdir}
  %define _fillupdir %{_localstatedir}/adm/fillup-templates
%endif

Name:           autoyast2
Version:        4.2.22
Release:        0
Summary:        YaST2 - Automated Installation
License:        GPL-2.0-only
Group:          System/YaST
Url:            https://github.com/yast/yast-autoinstallation

Source0:        autoyast2-%{version}.tar.bz2
Source1:        autoyast_en_html.tar.bz2

BuildRequires:  update-desktop-files
BuildRequires:  yast2-devtools >= 4.2.2
# control.rng
BuildRequires:  yast2-installation-control
# xmllint
BuildRequires:  libxml2-tools
# xsltproc for AutoinstClass
BuildRequires:  libxslt
BuildRequires:  rubygem(%{rb_default_ruby_abi}:rspec)
# Yast::Popup.ErrorAnyQuestion fixed
BuildRequires:  yast2 >= 4.0.60
# FileSystems.read_default_subvol_from_target
BuildRequires:  yast2-xml
BuildRequires:  yast2-transfer
BuildRequires:  yast2-services-manager
BuildRequires:  yast2-packager
BuildRequires:  yast2-update >= 3.3.0
BuildRequires:  yast2-network >= 3.1.145
BuildRequires:  yast2-slp
BuildRequires:  yast2-country
# Required for test suite testing one time sync
BuildRequires:       yast2-ntp-client >= 4.0.1
# Y2Storage::AutoinstProposal constructor receives a ProposalSettings object
BuildRequires:  yast2-storage-ng >= 4.2.55
# %%{_unitdir} macro definition is in a separate package since 13.1
%if 0%{?suse_version} >= 1310
BuildRequires:  systemd-rpm-macros
%else
BuildRequires:  systemd
%endif
BuildRequires:  rubygem(%rb_default_ruby_abi:yast-rake)

Requires:       autoyast2-installation = %{version}
Requires:       libxslt
# Y2Packager::ProductUpgrade.remove_obsolete_upgrades
Requires:       yast2 >= 4.2.1
Requires:       yast2-core
Requires:       yast2-country >= 3.1.13
# Moving security module to first installation stage
Requires:       yast2-security >= 4.1.1
Requires:       yast2-network >= 3.1.145
Requires:       yast2-schema >= 4.0.6
Requires:       yast2-transfer >= 2.21.0
Requires:       yast2-xml
# Y2Storage::AutoinstProposal constructor receives a ProposalSettings object
Requires:       yast2-storage-ng >= 4.2.55
Requires:       yast2-ruby-bindings >= 1.0.0

Conflicts:      yast2-installation < 3.1.166

Provides:       yast2-config-autoinst
Provides:       yast2-module-autoinst
Provides:       yast2-lib-autoinst

Obsoletes:      yast2-config-autoinst
Obsoletes:      yast2-module-autoinst
Obsoletes:      yast2-lib-autoinst

BuildArch:      noarch

Requires(post): %fillup_prereq

%description
This package is intended for management of the control files and the
AutoYaST2 configurations. This system should only be used by
experienced system administrators. Warning: AutoYaST2 performs the
installation without any user intervention, warnings, or confirmations
(unless specified otherwise in the control file).

This file contains YaST2-independent files needed to create
installation sources.

%package installation
Summary:        YaST2 - Auto Installation Modules
Group:          System/YaST

# Y2Storage::AutoinstIssues containing section information
BuildRequires:  yast2-storage-ng >= 4.0.15

# API for Disabled Modules (ProductControl)
Requires:       yast2 >= 2.16.36
# After API cleanup
Requires:       yast2
Requires:       yast2-bootloader
Requires:       yast2-core
Requires:       yast2-country
Requires:       yast2-ncurses
# Y2Packager::MediumType
Requires:       yast2-packager >= 4.2.25
# ServicesManagerTargetClass::BaseTargets
Requires:       yast2-services-manager >= 3.1.10
# Required for one time sync before installation
Requires:       yast2-ntp-client >= 4.0.1
Requires:       yast2-slp
Requires:       yast2-transfer >= 2.21.0
# storage-ng based version
Requires:       yast2-update >= 3.3.0
Requires:       yast2-xml
# "transact_by" key in PkgPropertiesAll()
Requires:       yast2-pkg-bindings >= 4.0.7
Requires:       yast2-ruby-bindings >= 1.0.0

Provides:       yast2-trans-autoinst
Obsoletes:      yast2-trans-autoinst

%description installation
This package performs auto-installation relying on a control file
generated with the autoyast2 package.

%prep
%setup -q

%check
%yast_check

%build

%install
%yast_install
%yast_metainfo

# Do not *blindly* remove the suse_update_desktop_file calls here. It is
# different from the code in the yast_install macro.
for d in %{buildroot}%{_datadir}/autoinstall/modules/*.desktop ; do
    %suse_update_desktop_file $d
done

%post
%{fillup_only -n autoinstall}

%files
%dir %{_sysconfdir}/autoinstall
%dir %{yast_yncludedir}/autoinstall
%dir %{_localstatedir}/lib/autoinstall/repository
%dir %{_localstatedir}/lib/autoinstall/repository/templates
%dir %{_localstatedir}/lib/autoinstall/repository/rules
%dir %{_localstatedir}/lib/autoinstall/repository/classes
%dir %{_localstatedir}/lib/autoinstall/tmp
%doc %{yast_docdir}

%{yast_desktopdir}
%{yast_metainfodir}
%{_datadir}/autoinstall/modules/*.desktop
%dir %{yast_yncludedir}
%{yast_yncludedir}/autoinstall/classes.rb
%{yast_yncludedir}/autoinstall/conftree.rb
%{yast_yncludedir}/autoinstall/dialogs.rb
%{yast_yncludedir}/autoinstall/script_dialogs.rb
%{yast_yncludedir}/autoinstall/general_dialogs.rb
%{yast_yncludedir}/autoinstall/wizards.rb
%{yast_yncludedir}/autoinstall/helps.rb
%dir %{yast_schemadir}
%dir %{yast_schemadir}/autoyast
%dir %{yast_schemadir}/autoyast/rnc
%{yast_schemadir}/autoyast/rnc/*.rnc

%dir %{yast_clientdir}
%{yast_clientdir}/general_auto.rb
%{yast_clientdir}/report_auto.rb
%{yast_clientdir}/classes_auto.rb
%{yast_clientdir}/scripts_auto.rb
%{yast_clientdir}/software_auto.rb
%{yast_clientdir}/storage_auto.rb
%{yast_clientdir}/autoyast.rb
%{yast_clientdir}/ayast_setup.rb

%dir %{yast_moduledir}
%{yast_moduledir}/AutoinstClass.rb

%{yast_icondir}

# additional files

%{_fillupdir}/sysconfig.autoinstall

%files installation
%dir %{yast_scrconfdir}
%{yast_scrconfdir}/autoinstall.scr
%{yast_scrconfdir}/cfg_autoinstall.scr
# autoinstall modules
%dir %{_datadir}/autoinstall
%dir %{_datadir}/autoinstall/modules

# systemd service file
%{_unitdir}/autoyast-initscripts.service

%dir %{_datadir}/autoinstall/xslt
%{_datadir}/autoinstall/xslt/merge.xslt
# config file

%dir %{yast_moduledir}
%{yast_moduledir}/AutoinstClone.rb
%dir %{yast_yncludedir}/autoinstall
%{yast_yncludedir}/autoinstall/io.rb
%{yast_yncludedir}/autoinstall/autoinst_dialogs.rb
%{yast_yncludedir}/autoinstall/AdvancedPartitionDialog.rb
%{yast_yncludedir}/autoinstall/DriveDialog.rb
%{yast_yncludedir}/autoinstall/PartitionDialog.rb
%{yast_yncludedir}/autoinstall/StorageDialog.rb
%{yast_yncludedir}/autoinstall/VolgroupDialog.rb
%{yast_yncludedir}/autoinstall/common.rb
%{yast_yncludedir}/autoinstall/tree.rb
%{yast_yncludedir}/autoinstall/types.rb

%dir %{yast_controldir}
%{yast_controldir}/*.xml

%{yast_moduledir}/AutoInstall.rb
%{yast_moduledir}/AutoinstScripts.rb
%{yast_moduledir}/AutoinstGeneral.rb
%{yast_moduledir}/AutoinstImage.rb
%{yast_moduledir}/Y2ModuleConfig.rb
%{yast_moduledir}/Profile.rb
%{yast_moduledir}/AutoinstFile.rb
%{yast_moduledir}/AutoinstConfig.rb
%{yast_moduledir}/AutoinstSoftware.rb
%{yast_moduledir}/AutoinstStorage.rb
%{yast_moduledir}/AutoInstallRules.rb
%{yast_moduledir}/ProfileLocation.rb
%{yast_moduledir}/AutoinstCommon.rb
%{yast_moduledir}/AutoinstDrive.rb
%{yast_moduledir}/AutoinstPartPlan.rb
%{yast_moduledir}/AutoinstPartition.rb
%{yast_moduledir}/AutoinstFunctions.rb

#clients
%{yast_clientdir}/inst_autoinit.rb
%{yast_clientdir}/inst_autoimage.rb
%{yast_clientdir}/inst_autosetup.rb
%{yast_clientdir}/inst_autoconfigure.rb
%{yast_clientdir}/inst_autopost.rb
%{yast_clientdir}/files_auto.rb
%{yast_clientdir}/autoinst_test_clone.rb
%{yast_clientdir}/autoinst_test_stage.rb
%{yast_clientdir}/autoinst_scripts1_finish.rb
%{yast_clientdir}/autoinst_scripts2_finish.rb
%{yast_clientdir}/ayast_probe.rb
%{yast_clientdir}/inst_autosetup_upgrade.rb
%{yast_clientdir}/inst_store_upgrade_software.rb
%{yast_clientdir}/clone_system.rb

%{yast_yncludedir}/autoinstall/xml.rb
%{yast_yncludedir}/autoinstall/ask.rb

%dir %{yast_libdir}/autoinstall
%{yast_libdir}/autoinstall/*.rb

%dir %{yast_libdir}/autoinstall/dialogs
%{yast_libdir}/autoinstall/dialogs/*.rb

%dir %{yast_libdir}/autoinstall/clients
%{yast_libdir}/autoinstall/clients/*.rb

%dir %{yast_libdir}/autoinstall/autoinst_issues
%{yast_libdir}/autoinstall/autoinst_issues/*.rb

# scripts
%{yast_ybindir}/fetch_image.sh
%{yast_ybindir}/autoyast-initscripts.sh

%license COPYING

%dir %{_localstatedir}/adm/autoinstall/
%dir %{_localstatedir}/adm/autoinstall/scripts
%dir %{_localstatedir}/adm/autoinstall/init.d
%dir %{_localstatedir}/adm/autoinstall/logs
%dir %{_localstatedir}/adm/autoinstall/files
%dir %{_localstatedir}/adm/autoinstall/cache
%dir %{_localstatedir}/lib/autoinstall
%dir %{_localstatedir}/lib/autoinstall/autoconf

%changelog
