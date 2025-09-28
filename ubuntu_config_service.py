# ubuntu_config_service.py
# This Flask application runs on your Ubuntu machine to receive configuration commands
# from the main Flask web app and execute system-level commands using subprocess.
# This version supports both real execution on a full Ubuntu OS (or privileged container)
# and mocking of system commands when in a Docker test environment.

import os
import subprocess
import json
import logging
from flask import Flask, request, jsonify
from datetime import datetime
import ipaddress # For CIDR conversion
import yaml # For YAML manipulation (install with pip install pyyaml)
import time # For sleep

# --- Logging Configuration ---
LOG_FILE = '/var/log/ubuntu_config_service.log'

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('UbuntuConfigService')

app = Flask(__name__)

# --- Docker Test Mode Flag ---
# This environment variable will be set in docker-compose.dev.yml for testing purposes.
# When True, timedatectl and netplan commands will be mocked.
IN_DOCKER_TEST_MODE = os.getenv("IN_DOCKER_TEST_MODE", "false").lower() == "true"
if IN_DOCKER_TEST_MODE:
    logger.warning("Running in Docker Test Mode: timedatectl and netplan commands will be mocked.")

# --- Constants ---
NETPLAN_CONFIG_DIR = '/etc/netplan/'
NETPLAN_CONFIG_FILE = os.path.join(NETPLAN_CONFIG_DIR, '01-vcns-network.yaml') # Dedicated config file
DEFAULT_NTP_SERVER = 'pool.ntp.org' # Default NTP server if none provided

# --- Helper Function to Run Shell Commands ---
def run_command(command_list, check_output=False):
    """
    Executes a shell command.
    Args:
        command_list (list): A list of strings representing the command and its arguments.
                             e.g., ['timedatectl', 'set-ntp', 'true']
        check_output (bool): If True, capture and return stdout/stderr.
                             If False, just check return code.
    Returns:
        tuple: (success_boolean, output_string_or_None)
    """
    try:
        logger.info(f"Executing command: {' '.join(command_list)}")

        # In Docker, we typically run as root, so 'sudo' is often not needed
        # and might not even be installed. We remove it from the command list.
        if command_list and command_list[0] == 'sudo':
            command_list = command_list[1:]
            logger.info(f"Removed 'sudo' from command. New command: {' '.join(command_list)}")

        # --- Mock system commands in Docker Test Mode ---
        if IN_DOCKER_TEST_MODE and command_list:
            command_name = command_list[0]
            if command_name in ['timedatectl', 'netplan', 'dhclient', 'systemctl', 'pkill']: # Added dhclient, systemctl, pkill
                mock_output = f"Mocked: {' '.join(command_list)} - This command would normally run on a full Ubuntu OS."
                logger.info(mock_output)
                # For dhclient -r, we want it to appear successful to the caller
                if command_name == 'dhclient' and '-r' in command_list:
                    return True, "Mocked: DHCP release successful."
                return True, mock_output
        # --- End Mocking ---

        # Always capture output when using check=True, to prevent AttributeError
        # and to get detailed error messages.
        result = subprocess.run(command_list, capture_output=True, text=True, check=True)

        output = result.stdout.strip()
        if output:
            logger.info(f"Command output: {output}")
        return True, output
    except subprocess.CalledProcessError as e:
        error_output = (e.stderr or e.stdout or "").strip()
        logger.error(f"Command failed with exit code {e.returncode}: {error_output}")
        logger.error(f"Full command attempted: {' '.join(command_list)}")

        if "command not found" in error_output.lower() or "No such file or directory" in error_output:
            return False, f"Command '{command_list[0]}' not found. Ensure it is installed and in PATH."

        # Specific error message for timedatectl in non-systemd environments
        if "systemd as init system (PID 1)" in error_output or "Failed to connect to bus" in error_output:
            return False, f"Cannot execute '{command_list[0]}': This command requires systemd as init system (PID 1) and D-Bus, which are typically not available in a standard Docker container. This service is intended for a full Ubuntu OS."

        return False, f"Command execution failed: {error_output}"
    except FileNotFoundError:
        return False, f"Command '{command_list[0]}' not found. Is it installed and in PATH?"
    except Exception as e:
        logger.error(f"An unexpected error occurred while executing command: {e}", exc_info=True)
        return False, f"An unexpected error occurred: {e}"

# --- Helper for CIDR conversion ---
def subnet_mask_to_cidr(subnet_mask):
    """Converts a subnet mask (e.g., '255.255.255.0') to CIDR notation (e.g., 24)."""
    try:
        network = ipaddress.IPv4Network(f'0.0.0.0/{subnet_mask}', strict=False)
        return network.prefixlen
    except ipaddress.AddressValueError:
        logger.error(f"Invalid subnet mask format: {subnet_mask}")
        return None
    except Exception as e:
        logger.error(f"Error converting subnet mask to CIDR: {e}")
        return None

# --- Ubuntu 16.04 Legacy Network Configuration ---
def _get_ubuntu_version():
    """Detect Ubuntu version to determine networking approach."""
    try:
        with open('/etc/os-release', 'r') as f:
            content = f.read()
            if 'VERSION_ID="16.04"' in content:
                return "16.04"
            elif 'VERSION_ID="18.04"' in content:
                return "18.04"
        return "modern"
    except:
        return "modern"

def _configure_legacy_network_ubuntu16(ip_type, ip_address, subnet_mask, gateway, dns_server, interface_name):
    """Configure network using legacy /etc/network/interfaces for Ubuntu 16.04."""
    interfaces_file = '/etc/network/interfaces'
    
    try:
        if ip_type == 'dynamic':
            interfaces_config = f"""auto lo
iface lo inet loopback

auto {interface_name}
iface {interface_name} inet dhcp
"""
        elif ip_type == 'static':
            if not all([ip_address, subnet_mask, gateway]):
                raise ValueError("For static IP, ipAddress, subnetMask, and gateway are required.")
            
            dns_config = f"    dns-nameservers {dns_server}" if dns_server else "    dns-nameservers 8.8.8.8"
            interfaces_config = f"""auto lo
iface lo inet loopback

auto {interface_name}
iface {interface_name} inet static
    address {ip_address}
    netmask {subnet_mask}
    gateway {gateway}
{dns_config}
"""
        else:
            raise ValueError(f"Invalid ipType: {ip_type}. Must be 'dynamic' or 'static'.")
        
        # Backup existing file
        run_command(['cp', interfaces_file, f'{interfaces_file}.backup'])
        
        # Write new configuration
        with open(interfaces_file, 'w') as f:
            f.write(interfaces_config)
        
        logger.info(f"Network configuration written to {interfaces_file}")
        
        # Apply configuration for Ubuntu 16.04
        # First release DHCP if switching to static
        if ip_type == 'static':
            run_command(['dhclient', '-r', interface_name])
        
        # Restart networking
        success, output = run_command(['service', 'networking', 'restart'])
        if not success:
            # Try alternative method
            success, output = run_command(['ifdown', interface_name])
            if success:
                success, output = run_command(['ifup', interface_name])
        
        if not success:
            raise Exception(f"Failed to apply network configuration: {output}")
        
        logger.info("Network configuration applied successfully for Ubuntu 16.04")
        return True, "Network configuration applied successfully."
        
    except Exception as e:
        logger.error(f"Error configuring legacy network: {e}")
        # Restore backup if available
        try:
            run_command(['cp', f'{interfaces_file}.backup', interfaces_file])
        except:
            pass
        return False, f"Error applying network settings: {e}"

# --- Ubuntu 16.04 Legacy Time Configuration ---
def _configure_legacy_time_ubuntu16(time_type, ntp_server, manual_date, manual_time):
    """Configure time using legacy methods for Ubuntu 16.04."""
    try:
        if time_type == 'ntp':
            logger.info(f"Setting up NTP synchronization for Ubuntu 16.04")
            
            # Install ntpsec if not present (in case it's missing)
            run_command(['apt-get', 'update'])
            run_command(['apt-get', 'install', '-y', 'ntpsec'])
            
            # Stop ntp service first
            run_command(['systemctl', 'stop', 'ntp']) if run_command(['which', 'systemctl'])[0] else run_command(['service', 'ntp', 'stop'])
            
            # Configure NTP server in /etc/ntp.conf
            ntp_config = f"""# NTP configuration for Ubuntu 16.04
driftfile /var/lib/ntp/ntp.drift
statistics loopstats peerstats clockstats
filegen loopstats file loopstats type day enable
filegen peerstats file peerstats type day enable
filegen clockstats file clockstats type day enable

# Use specified NTP server or default
server {ntp_server or 'pool.ntp.org'} iburst
server 0.ubuntu.pool.ntp.org iburst
server 1.ubuntu.pool.ntp.org iburst

# Access control
restrict -4 default kod notrap nomodify nopeer noquery limited
restrict -6 default kod notrap nomodify nopeer noquery limited
restrict 127.0.0.1
restrict ::1

# Local clock fallback
server 127.127.1.0
fudge 127.127.1.0 stratum 10
"""
            
            with open('/etc/ntp.conf', 'w') as f:
                f.write(ntp_config)
            
            # Start and enable NTP service
            success, output = run_command(['systemctl', 'start', 'ntp']) if run_command(['which', 'systemctl'])[0] else run_command(['service', 'ntp', 'start'])
            if not success:
                raise Exception(f"Failed to start NTP service: {output}")
            
            # Force time sync (use ntpsec-ntpdate instead of ntpdate)
            run_command(['ntpsec-ntpdate', '-s', ntp_server or 'pool.ntp.org'])
            
            logger.info("NTP synchronization configured for Ubuntu 16.04")
            return True, "NTP synchronization enabled successfully."
            
        elif time_type == 'manual':
            if not all([manual_date, manual_time]):
                raise ValueError("For manual time, manualDate and manualTime are required.")
            
            # Validate date/time format
            try:
                datetime.strptime(f"{manual_date} {manual_time}", "%Y-%m-%d %H:%M")
            except ValueError:
                raise ValueError("Invalid date or time format. Use YYYY-MM-DD and HH:MM.")
            
            logger.info(f"Setting manual time for Ubuntu 16.04: {manual_date} {manual_time}")
            
            # Stop NTP service to allow manual time setting
            run_command(['systemctl', 'stop', 'ntp']) if run_command(['which', 'systemctl'])[0] else run_command(['service', 'ntp', 'stop'])
            
            # Set the date and time using date command (Ubuntu 16.04 compatible)
            date_string = f"{manual_date} {manual_time}:00"
            success, output = run_command(['date', '-s', date_string])
            
            if not success:
                raise Exception(f"Failed to set manual time: {output}")
            
            # Update hardware clock
            run_command(['hwclock', '--systohc'])
            
            logger.info("Manual time set successfully for Ubuntu 16.04")
            return True, "Manual time set successfully."
        else:
            raise ValueError(f"Invalid timeType: {time_type}. Must be 'ntp' or 'manual'.")
            
    except Exception as e:
        logger.error(f"Error configuring legacy time: {e}")
        return False, f"Error applying time settings: {e}"

# --- Netplan Configuration Functions ---
def _get_network_interface_name():
    """
    Attempts to find a common network interface name (e.g., eth0, enp0sX).
    This is a heuristic and might need to be made configurable for robust deployments.
    """
    try:
        # List common interface types
        interfaces = [f.name for f in os.scandir('/sys/class/net') if f.is_dir()]
        
        # Prioritize wired interfaces
        for iface in interfaces:
            if iface.startswith('eth') or iface.startswith('enp'):
                logger.info(f"Detected primary network interface: {iface}")
                return iface
        
        # Fallback to any detected interface if no common wired one is found
        if interfaces:
            logger.warning(f"No common wired interface found. Using first detected interface: {interfaces[0]}")
            return interfaces[0]

    except Exception as e:
        logger.error(f"Error detecting network interface: {e}")
    
    logger.error("Could not detect any network interface. Please specify manually.")
    return None # Indicate failure to detect

def _generate_netplan_yaml(ip_type, ip_address, subnet_mask, gateway, dns_server, interface_name):
    """
    Generates the Netplan YAML configuration based on the provided settings.
    """
    if not interface_name:
        raise ValueError("Network interface name is required to generate Netplan configuration.")

    netplan_config = {
        'network': {
            'version': 2,
            'renderer': 'networkd', # Or 'NetworkManager' if that's preferred
            'ethernets': {
                interface_name: {}
            }
        }
    }
    
    if ip_type == 'dynamic':
        netplan_config['network']['ethernets'][interface_name]['dhcp4'] = True
        logger.info(f"Generated Netplan YAML for dynamic IP on {interface_name}.")
    elif ip_type == 'static':
        if not all([ip_address, subnet_mask, gateway]):
            raise ValueError("For static IP, ipAddress, subnetMask, and gateway are required.")
        
        cidr = subnet_mask_to_cidr(subnet_mask)
        if cidr is None:
            raise ValueError("Invalid subnet mask provided for CIDR conversion.")

        netplan_config['network']['ethernets'][interface_name]['dhcp4'] = False
        netplan_config['network']['ethernets'][interface_name]['addresses'] = [f"{ip_address}/{cidr}"]
        netplan_config['network']['ethernets'][interface_name]['routes'] = [
            {'to': 'default', 'via': gateway}
        ]
        if dns_server:
            netplan_config['network']['ethernets'][interface_name]['nameservers'] = {
                'addresses': [dns_server]
            }
        logger.info(f"Generated Netplan YAML for static IP {ip_address}/{cidr} on {interface_name}.")
    else:
        raise ValueError(f"Invalid ipType: {ip_type}. Must be 'dynamic' or 'static'.")
    
    return netplan_config

def _write_and_apply_netplan(netplan_data):
    """
    Writes the Netplan configuration to a YAML file and applies it.
    """
    try:
        # Ensure the directory exists (it should be mounted from host)
        os.makedirs(NETPLAN_CONFIG_DIR, exist_ok=True)
        
        # Write the YAML content to the dedicated Netplan file
        with open(NETPLAN_CONFIG_FILE, 'w') as f:
            yaml.dump(netplan_data, f, default_flow_style=False, sort_keys=False)
        logger.info(f"Netplan configuration written to {NETPLAN_CONFIG_FILE}")

        # Apply the Netplan configuration
        success, output = run_command(['netplan', 'apply'])
        if not success:
            raise Exception(f"Failed to apply Netplan configuration: {output}")
        
        logger.info("Netplan configuration applied successfully.")
        return True, "Netplan configuration applied successfully."
    except Exception as e:
        logger.error(f"Error writing or applying Netplan configuration: {e}")
        return False, f"Error applying network settings: {e}"

# --- Flask Routes ---
@app.route('/apply_network_settings', methods=['POST'])
def apply_network_settings():
    """
    Receives network configuration (dynamic/static IP) and applies them via appropriate method.
    Uses legacy /etc/network/interfaces for Ubuntu 16.04, Netplan for modern versions.
    """
    data = request.get_json()
    if not data:
        logger.warning("No JSON data received for network settings.")
        return jsonify({"status": "error", "message": "No JSON data provided."}), 400

    ip_type = data.get('ipType')
    ip_address = data.get('ipAddress')
    subnet_mask = data.get('subnetMask')
    gateway = data.get('gateway')
    dns_server = data.get('dnsServer')

    logger.info(f"Received network configuration request: {data}")

    try:
        interface_name = _get_network_interface_name()
        if not interface_name:
            return jsonify({"status": "error", "message": "Could not detect network interface. Please configure manually."}), 500

        # Detect Ubuntu version and use appropriate configuration method
        ubuntu_version = _get_ubuntu_version()
        logger.info(f"Detected Ubuntu version: {ubuntu_version}")
        
        if ubuntu_version == "16.04":
            # Use legacy configuration for Ubuntu 16.04
            success, message = _configure_legacy_network_ubuntu16(ip_type, ip_address, subnet_mask, gateway, dns_server, interface_name)
        else:
            # Use Netplan for modern Ubuntu versions
            netplan_config = _generate_netplan_yaml(ip_type, ip_address, subnet_mask, gateway, dns_server, interface_name)
            success, message = _write_and_apply_netplan(netplan_config)

        if success:
            logger.info(f"Network settings applied: {message}")
            return jsonify({"status": "success", "message": message}), 200
        else:
            logger.error(f"Failed to apply network settings: {message}")
            return jsonify({"status": "error", "message": message}), 500
    except ValueError as ve:
        logger.warning(f"Invalid input for network settings: {ve}")
        return jsonify({"status": "error", "message": str(ve)}), 400
    except Exception as e:
        logger.critical(f"Unexpected error in apply_network_settings: {e}", exc_info=True)
        return jsonify({"status": "error", "message": f"An unexpected error occurred: {e}"}), 500

@app.route('/disable_dhcp', methods=['POST'])
def disable_dhcp():
    """
    Disables DHCP on the network interface.
    This is called by the main Flask app when a static IP is configured.
    """
    logger.info("Received request to disable DHCP.")
    try:
        interface_name = _get_network_interface_name()
        if not interface_name:
            return jsonify({"status": "error", "message": "Could not detect network interface to disable DHCP."}), 500

        # 1. Release current DHCP lease
        success_release, output_release = run_command(['dhclient', '-r', interface_name])
        if not success_release and "No DHCPOFF" not in output_release: # "No DHCPOFF" means no active lease to release, which is fine
            logger.warning(f"Failed to release DHCP lease on {interface_name}: {output_release}. Proceeding anyway.")
        else:
            logger.info(f"DHCP lease released on {interface_name}.")

        # 2. Stop and disable NetworkManager (if active and managing the interface)
        # NetworkManager can interfere with Netplan if it's managing the same interface.
        # This step ensures Netplan has full control.
        success_nm_stop, output_nm_stop = run_command(['systemctl', 'stop', 'NetworkManager'])
        if not success_nm_stop and "not running" not in output_nm_stop and "Unit NetworkManager.service not loaded" not in output_nm_stop:
            logger.warning(f"Failed to stop NetworkManager: {output_nm_stop}. Proceeding anyway.")
        else:
            logger.info("NetworkManager stopped (if it was running).")

        success_nm_disable, output_nm_disable = run_command(['systemctl', 'disable', 'NetworkManager'])
        if not success_nm_disable and "No such file or directory" not in output_nm_disable and "Unit NetworkManager.service not loaded" not in output_nm_disable:
            logger.warning(f"Failed to disable NetworkManager: {output_nm_disable}. Proceeding anyway.")
        else:
            logger.info("NetworkManager disabled (if it was enabled).")

        # 3. Stop and disable dhclient (if it's running as a standalone service)
        success_dhclient_stop, output_dhclient_stop = run_command(['systemctl', 'stop', 'isc-dhcp-client'])
        if not success_dhclient_stop and "not running" not in output_dhclient_stop and "Unit isc-dhcp-client.service not loaded" not in output_dhclient_stop:
            logger.warning(f"Failed to stop isc-dhcp-client: {output_dhclient_stop}. Proceeding anyway.")
        else:
            logger.info("isc-dhcp-client stopped (if it was running).")

        success_dhclient_disable, output_dhclient_disable = run_command(['systemctl', 'disable', 'isc-dhcp-client'])
        if not success_dhclient_disable and "No such file or directory" not in output_dhclient_disable and "Unit isc-dhcp-client.service not loaded" not in output_dhclient_disable:
            logger.warning(f"Failed to disable isc-dhcp-client: {output_dhclient_disable}. Proceeding anyway.")
        else:
            logger.info("isc-dhcp-client disabled (if it was enabled).")

        # 4. Kill any remaining dhclient processes
        success_pkill_dhclient, output_pkill_dhclient = run_command(['pkill', 'dhclient'])
        if not success_pkill_dhclient and "No process found" not in output_pkill_dhclient:
             logger.warning(f"Failed to pkill dhclient processes: {output_pkill_dhclient}. Proceeding anyway.")
        else:
            logger.info("Any remaining dhclient processes killed.")

        logger.info("DHCP successfully disabled and related services stopped/disabled.")
        return jsonify({"status": "success", "message": "DHCP disabled successfully."}), 200

    except Exception as e:
        logger.critical(f"Unexpected error in disable_dhcp: {e}", exc_info=True)
        return jsonify({"status": "error", "message": f"An unexpected error occurred while disabling DHCP: {e}"}), 500


@app.route('/apply_time_settings', methods=['POST'])
def apply_time_settings():
    """
    Receives time synchronization settings (NTP or manual) and applies them.
    Uses legacy methods for Ubuntu 16.04, timedatectl for modern versions.
    """
    data = request.get_json()
    if not data:
        logger.warning("No JSON data received for time settings.")
        return jsonify({"status": "error", "message": "No JSON data provided."}), 400

    time_type = data.get('timeType')
    ntp_server = data.get('ntpServer')
    manual_date = data.get('manualDate')
    manual_time = data.get('manualTime')

    logger.info(f"Received time configuration request: {data}")

    try:
        # Detect Ubuntu version and use appropriate time configuration method
        ubuntu_version = _get_ubuntu_version()
        logger.info(f"Detected Ubuntu version: {ubuntu_version}")
        
        if ubuntu_version == "16.04":
            # Use legacy time configuration for Ubuntu 16.04
            success, message = _configure_legacy_time_ubuntu16(time_type, ntp_server, manual_date, manual_time)
        else:
            # Use timedatectl for modern Ubuntu versions
            if time_type == 'ntp':
                logger.info(f"Setting time synchronization to NTP with server: {ntp_server if ntp_server else DEFAULT_NTP_SERVER}")
                
                # Disable manual NTP first
                success_disable, error_disable = run_command(['timedatectl', 'set-ntp', 'false'])
                if not success_disable:
                    logger.error(f"Failed to disable NTP: {error_disable}")
                    return jsonify({"status": "error", "message": f"Failed to disable NTP: {error_disable}"}), 500

                # Enable NTP
                success_enable, error_enable = run_command(['timedatectl', 'set-ntp', 'true'])
                if not success_enable:
                    logger.error(f"Failed to enable NTP: {error_enable}")
                    return jsonify({"status": "error", "message": f"Failed to enable NTP: {error_enable}"}), 500
                
                success, message = True, "NTP synchronization enabled successfully."
                
            elif time_type == 'manual':
                if not all([manual_date, manual_time]):
                    return jsonify({"status": "error", "message": "For manual time, manualDate and manualTime are required."}), 400

                try:
                    datetime.strptime(f"{manual_date} {manual_time}", "%Y-%m-%d %H:%M")
                except ValueError:
                    return jsonify({"status": "error", "message": "Invalid date or time format. Use YYYY-MM-DD and HH:MM."}), 400

                logger.info(f"Setting manual time to: {manual_date} {manual_time}")
                # Disable NTP first
                success_disable, error_disable = run_command(['timedatectl', 'set-ntp', 'false'])
                if not success_disable:
                    return jsonify({"status": "error", "message": f"Failed to disable NTP: {error_disable}"}), 500

                # Set the date and time
                set_time_command = ['timedatectl', 'set-time', f"{manual_date} {manual_time}:00"]
                success_set_time, error_set_time = run_command(set_time_command)
                
                if success_set_time:
                    success, message = True, "Manual time set successfully."
                else:
                    success, message = False, f"Failed to set manual time: {error_set_time}"
            else:
                return jsonify({"status": "error", "message": "Invalid timeType. Must be 'ntp' or 'manual'."}), 400

        # Return result
        if success:
            logger.info(f"Time settings applied: {message}")
            return jsonify({"status": "success", "message": message}), 200
        else:
            logger.error(f"Failed to apply time settings: {message}")
            return jsonify({"status": "error", "message": message}), 500
            
    except ValueError as ve:
        logger.warning(f"Invalid input for time settings: {ve}")
        return jsonify({"status": "error", "message": str(ve)}), 400
    except Exception as e:
        logger.critical(f"Unexpected error in apply_time_settings: {e}", exc_info=True)
        return jsonify({"status": "error", "message": f"An unexpected error occurred: {e}"}), 500

# --- Main Execution ---
if __name__ == '__main__':
    logger.info("Starting Ubuntu Configuration Service...")
    # Ensure Netplan config directory exists on the host (via mount)
    # This mkdir is safe even if the directory already exists.
    # It's important for the case where the service runs natively or in a privileged container.
    os.makedirs(NETPLAN_CONFIG_DIR, exist_ok=True)
    app.run(
        host='0.0.0.0',
        port=5002,
        debug=False,
        threaded=True,
        use_reloader=False,
        use_debugger=False
    )

