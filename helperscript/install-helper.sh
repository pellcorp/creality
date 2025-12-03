#!/bin/sh

# everything else in the script assumes its cloned to /usr/data/pellcorp
# so we must verify this or shit goes wrong
if [ "$(dirname $(readlink -f $0))" != "/usr/data/pellcorp/helperscript" ]; then
  >&2 echo "FATAL: This git repo must be cloned to /usr/data/pellcorp"
  exit 1
fi

if [ ! -f /usr/data/printer_data/config/printer.cfg ]; then
  >&2 echo "ERROR: Printer data not setup"
  exit 1
fi

if [ -f /usr/data/pellcorp.done ]; then
  >&2 echo "ERROR: SimpleAF is installed"
  exit 1
fi

if [ ! -d /usr/data/helper-script ]; then
    git config --global http.sslVerify false
    git clone https://github.com/Guilouz/Creality-Helper-Script.git /usr/data/helper-script || exit $?
fi

sed -i 's/^update_menu/#update_menu/g' /usr/data/helper-script/helper.sh || exit $?
sed -i 's/^main_menu/#main_menu/g' /usr/data/helper-script/helper.sh || exit $?
echo 'run $1 $2 || exit $?' >> /usr/data/helper-script/helper.sh || exit $?

sed -i 's/install_msg.*//g' -i /usr/data/helper-script/scripts/moonraker_nginx.sh || exit $?
sed -i 's/local yn/local yn=y/g' -i /usr/data/helper-script/scripts/moonraker_nginx.sh || exit $?
# moonraker-env extraction too verbose
sed -i 's/tar -xvf/ tar -xf/g'  -i /usr/data/helper-script/scripts/moonraker_nginx.sh || exit $?

sed -i 's/install_msg.*//g' -i /usr/data/helper-script/scripts/fluidd.sh || exit $?
sed -i 's/local yn/local yn=y/g' -i /usr/data/helper-script/scripts/fluidd.sh || exit $?

sed -i 's/remove_msg.*//g' -i /usr/data/helper-script/scripts/creality_web_interface.sh || exit $?
sed -i 's/local yn/local yn=y/g' -i /usr/data/helper-script/scripts/creality_web_interface.sh || exit $?

sed -i 's/install_msg.*//g' -i /usr/data/helper-script/scripts/kamp.sh || exit $?
sed -i 's/local yn/local yn=y/g' -i /usr/data/helper-script/scripts/kamp.sh || exit $?
sed -i 's/local yn=y_prusa/local yn_prusa=n/g' -i /usr/data/helper-script/scripts/kamp.sh || exit $?
sed -i 's/read -p.*//g' -i /usr/data/helper-script/scripts/kamp.sh || exit $?

sed -i 's/install_msg.*//g' -i /usr/data/helper-script/scripts/guppy_screen.sh || exit $?
sed -i 's/local yn/local yn=y/g' -i /usr/data/helper-script/scripts/guppy_screen.sh || exit $?
sed -i 's/read -p.*//g' -i /usr/data/helper-script/scripts/guppy_screen.sh || exit $?
sed -i 's/local theme_choice/local theme_choice=nightly/g' -i /usr/data/helper-script/scripts/guppy_screen.sh || exit $?

sed -i 's/install_msg.*//g' -i /usr/data/helper-script/scripts/gcode_shell_command.sh || exit $?
sed -i 's/local yn/local yn=y/g' -i /usr/data/helper-script/scripts/gcode_shell_command.sh || exit $?

sed -i 's/install_msg.*//g' -i /usr/data/helper-script/scripts/improved_shapers.sh || exit $?
sed -i 's/local yn/local yn=y/g' -i /usr/data/helper-script/scripts/improved_shapers.sh || exit $?

sh /usr/data/helper-script/helper.sh install_moonraker_nginx install_menu_ui_k1 || exit $?
sync

echo "Waiting for moonraker ..."
while true; do
    KLIPPER_PATH=$(curl localhost:7125/printer/info 2> /dev/null | jq -r .result.klipper_path)
    if [ "$KLIPPER_PATH" = "/usr/share/klipper" ]; then
        break;
    fi
    sleep 1
done

sh /usr/data/helper-script/helper.sh install_fluidd install_menu_ui_k1 || exit $?
sync

sh /usr/data/helper-script/helper.sh remove_creality_web_interface install_menu_ui_k1 || exit $?
sync

sh /usr/data/helper-script/helper.sh install_kamp install_menu_ui_k1 || exit $?
sync

sh /usr/data/helper-script/helper.sh install_gcode_shell_command install_menu_ui_k1 || exit $?
sync

sh /usr/data/helper-script/helper.sh install_improved_shapers install_menu_ui_k1 || exit $?
sync

sh /usr/data/helper-script/helper.sh install_guppy_screen customize_menu_ui_k1 || exit $?
sync

echo "Done!"
