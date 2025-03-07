{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.hardware.opengl;

  kernelPackages = config.boot.kernelPackages;

  videoDrivers = config.services.xserver.videoDrivers;

  package = pkgs.buildEnv {
    name = "opengl-drivers";
    paths = [ cfg.package ] ++ cfg.extraPackages;
  };

  package32 = pkgs.buildEnv {
    name = "opengl-drivers-32bit";
    paths = [ cfg.package32 ] ++ cfg.extraPackages32;
  };

in

{

  imports = [
    (mkRenamedOptionModule [ "services" "xserver" "vaapiDrivers" ] [ "hardware" "opengl" "extraPackages" ])
    (mkRemovedOptionModule [ "hardware" "opengl" "s3tcSupport" ] "S3TC support is now always enabled in Mesa.")
  ];

  options = {

    hardware.opengl = {
      enable = mkOption {
        description = lib.mdDoc ''
          Whether to enable OpenGL drivers. This is needed to enable
          OpenGL support in X11 systems, as well as for Wayland compositors
          like sway and Weston. It is enabled by default
          by the corresponding modules, so you do not usually have to
          set it yourself, only if there is no module for your wayland
          compositor of choice. See services.xserver.enable and
          programs.sway.enable.
        '';
        type = types.bool;
        default = false;
      };

      driSupport = mkOption {
        type = types.bool;
        default = true;
        description = lib.mdDoc ''
          Whether to enable accelerated OpenGL rendering through the
          Direct Rendering Interface (DRI).
        '';
      };

      driSupport32Bit = mkOption {
        type = types.bool;
        default = false;
        description = lib.mdDoc ''
          On 64-bit systems, whether to support Direct Rendering for
          32-bit applications (such as Wine).  This is currently only
          supported for the `nvidia` as well as
          `Mesa`.
        '';
      };

      package = mkOption {
        type = types.package;
        internal = true;
        default = cfg.mesaPackage;
        description = lib.mdDoc ''
          The package that provides the OpenGL implementation.

          The default is Mesa's drivers which should cover all OpenGL-capable
          hardware. If you want to use another Mesa version, adjust
          {option}`mesaPackage`.
        '';
      };
      package32 = mkOption {
        type = types.package;
        internal = true;
        default = cfg.mesaPackage32;
        description = lib.mdDoc ''
          Same as {option}`package` but for the 32-bit OpenGL implementation on
          64-bit systems. Used when {option}`driSupport32Bit` is set.
        '';
      };

      mesaPackage = mkOption {
        type = types.package;
        default = pkgs.mesa;
        defaultText = literalExpression "pkgs.mesa";
        example = literalExpression "pkgs.mesa_22";
        description = lib.mdDoc ''
          The Mesa driver package used for rendering support on the system.

          You should only need to adjust this if you require a newer Mesa
          version for your hardware or because you need to patch a bug.
        '';
        apply = mesa: mesa.drivers or (throw "`mesa` package must have a `drivers` output.");
      };
      mesaPackage32 = mkOption {
        type = types.package;
        default = pkgs.pkgsi686Linux.mesa;
        defaultText = literalExpression "pkgs.pkgsi686Linux.mesa";
        example = literalExpression "pkgs.pkgsi686Linux.mesa_22";
        description = lib.mdDoc ''
          Same as {option}`mesaPackage` but for the 32-bit Mesa on 64-bit
          systems. Used when {option}`driSupport32Bit` is set.
        '';
        apply = mesa: mesa.drivers or (throw "`mesa` package must have a `drivers` output.");
      };

      extraPackages = mkOption {
        type = types.listOf types.package;
        default = [];
        example = literalExpression "with pkgs; [ intel-media-driver intel-ocl vaapiIntel ]";
        description = lib.mdDoc ''
          Additional packages to add to OpenGL drivers.
          This can be used to add OpenCL drivers, VA-API/VDPAU drivers etc.

          ::: {.note}
          intel-media-driver supports hardware Broadwell (2014) or newer. Older hardware should use the mostly unmaintained vaapiIntel driver.
          :::
        '';
      };
      extraPackages32 = mkOption {
        type = types.listOf types.package;
        default = [];
        example = literalExpression "with pkgs.pkgsi686Linux; [ intel-media-driver vaapiIntel ]";
        description = lib.mdDoc ''
          Additional packages to add to 32-bit OpenGL drivers on 64-bit systems.
          Used when {option}`driSupport32Bit` is set. This can be used to add OpenCL drivers, VA-API/VDPAU drivers etc.

          ::: {.note}
          intel-media-driver supports hardware Broadwell (2014) or newer. Older hardware should use the mostly unmaintained vaapiIntel driver.
          :::
        '';
      };

      setLdLibraryPath = mkOption {
        type = types.bool;
        internal = true;
        default = false;
        description = lib.mdDoc ''
          Whether the `LD_LIBRARY_PATH` environment variable
          should be set to the locations of driver libraries. Drivers which
          rely on overriding libraries should set this to true. Drivers which
          support `libglvnd` and other dispatch libraries
          instead of overriding libraries should not set this.
        '';
      };
    };

  };

  config = mkIf cfg.enable {
    assertions = [
      { assertion = cfg.driSupport32Bit -> pkgs.stdenv.isx86_64;
        message = "Option driSupport32Bit only makes sense on a 64-bit system.";
      }
      { assertion = cfg.driSupport32Bit -> (config.boot.kernelPackages.kernel.features.ia32Emulation or false);
        message = "Option driSupport32Bit requires a kernel that supports 32bit emulation";
      }
    ];

    systemd.tmpfiles.rules = [
      "L+ /run/opengl-driver - - - - ${package}"
      (
        if pkgs.stdenv.isi686 then
          "L+ /run/opengl-driver-32 - - - - opengl-driver"
        else if cfg.driSupport32Bit then
          "L+ /run/opengl-driver-32 - - - - ${package32}"
        else
          "r /run/opengl-driver-32"
      )
    ];

    environment.sessionVariables.LD_LIBRARY_PATH = mkIf cfg.setLdLibraryPath
      ([ "/run/opengl-driver/lib" ] ++ optional cfg.driSupport32Bit "/run/opengl-driver-32/lib");

    boot.extraModulePackages = optional (elem "virtualbox" videoDrivers) kernelPackages.virtualboxGuestAdditions;
  };
}
