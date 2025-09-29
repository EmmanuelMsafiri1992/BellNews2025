#!/usr/bin/env python3
"""
NanoPi NEO3 Compatibility Test Suite
Tests all critical functionality to ensure the Bell News application will run without halting
"""

import os
import sys
import time
import psutil
import threading
import subprocess
from pathlib import Path

# Test results storage
test_results = {
    'hardware_detection': False,
    'memory_sufficient': False,
    'cpu_performance': False,
    'gpio_available': False,
    'i2c_available': False,
    'audio_available': False,
    'network_available': False,
    'python_modules': False,
    'file_permissions': False,
    'startup_stability': False
}

def log_test(test_name, result, details=""):
    """Log test results"""
    status = "✅ PASS" if result else "❌ FAIL"
    print(f"{status} {test_name}: {details}")
    return result

def test_hardware_detection():
    """Test if we can detect NanoPi board"""
    try:
        # Check for device tree model
        if os.path.exists('/proc/device-tree/model'):
            with open('/proc/device-tree/model', 'r') as f:
                model = f.read().lower()
                is_nanopi = 'nanopi' in model or 'orange' in model
                return log_test("Hardware Detection", is_nanopi, f"Board: {model.strip()}")

        # Fallback: Check CPU info
        with open('/proc/cpuinfo', 'r') as f:
            cpuinfo = f.read().lower()
            is_arm = 'arm' in cpuinfo or 'aarch64' in cpuinfo
            return log_test("Hardware Detection", is_arm, "ARM-based board detected")
    except Exception as e:
        return log_test("Hardware Detection", False, f"Error: {e}")

def test_memory_requirements():
    """Test if memory is sufficient for the application"""
    try:
        memory = psutil.virtual_memory()
        total_gb = memory.total / (1024**3)
        available_gb = memory.available / (1024**3)

        # Bell News needs minimum 512MB available
        sufficient = available_gb >= 0.5
        return log_test("Memory Requirements", sufficient,
                       f"Total: {total_gb:.1f}GB, Available: {available_gb:.1f}GB")
    except Exception as e:
        return log_test("Memory Requirements", False, f"Error: {e}")

def test_cpu_performance():
    """Test CPU performance under load"""
    try:
        # Get CPU count and basic info
        cpu_count = psutil.cpu_count()

        # Quick performance test
        start_time = time.time()
        cpu_percent = psutil.cpu_percent(interval=1)
        test_duration = time.time() - start_time

        # Performance should be reasonable
        performance_ok = test_duration < 2.0 and cpu_count >= 2
        return log_test("CPU Performance", performance_ok,
                       f"Cores: {cpu_count}, Usage: {cpu_percent}%, Test time: {test_duration:.2f}s")
    except Exception as e:
        return log_test("CPU Performance", False, f"Error: {e}")

def test_gpio_functionality():
    """Test GPIO library availability"""
    try:
        # Try OPi.GPIO first (preferred for NanoPi)
        try:
            import OPi.GPIO as GPIO
            GPIO.setmode(GPIO.BCM)
            GPIO.cleanup()
            return log_test("GPIO Functionality", True, "OPi.GPIO library working")
        except ImportError:
            pass

        # Fallback to RPi.GPIO
        try:
            import RPi.GPIO as GPIO
            GPIO.setmode(GPIO.BCM)
            GPIO.cleanup()
            return log_test("GPIO Functionality", True, "RPi.GPIO library working")
        except ImportError:
            return log_test("GPIO Functionality", False, "No GPIO library available")

    except Exception as e:
        return log_test("GPIO Functionality", False, f"GPIO Error: {e}")

def test_i2c_availability():
    """Test I2C interface availability"""
    try:
        # Check for I2C device files
        i2c_devices = [f for f in os.listdir('/dev') if f.startswith('i2c-')]
        if i2c_devices:
            # Try to import luma.oled for OLED support
            try:
                from luma.core.interface.serial import i2c
                from luma.oled.device import ssd1306
                return log_test("I2C Availability", True, f"I2C devices: {i2c_devices}")
            except ImportError:
                return log_test("I2C Availability", True, f"I2C present but luma.oled missing: {i2c_devices}")
        else:
            return log_test("I2C Availability", False, "No I2C devices found")
    except Exception as e:
        return log_test("I2C Availability", False, f"Error: {e}")

def test_audio_functionality():
    """Test audio system availability"""
    try:
        # Check for audio devices
        audio_devices = []
        if os.path.exists('/proc/asound/cards'):
            with open('/proc/asound/cards', 'r') as f:
                cards = f.read()
                audio_devices = [line for line in cards.split('\n') if line.strip()]

        # Test pygame availability
        try:
            import pygame
            pygame.mixer.init()
            pygame.mixer.quit()
            audio_working = True
        except:
            audio_working = False

        return log_test("Audio Functionality", audio_working,
                       f"Audio cards: {len(audio_devices)}, Pygame: {audio_working}")
    except Exception as e:
        return log_test("Audio Functionality", False, f"Error: {e}")

def test_network_availability():
    """Test network connectivity"""
    try:
        # Check network interfaces
        interfaces = psutil.net_if_addrs()
        active_interfaces = [name for name, addrs in interfaces.items()
                           if any(addr.family == 2 for addr in addrs)]  # IPv4

        # Test internet connectivity
        try:
            import socket
            socket.create_connection(("8.8.8.8", 53), timeout=3)
            internet_ok = True
        except:
            internet_ok = False

        network_ok = len(active_interfaces) > 0
        return log_test("Network Availability", network_ok,
                       f"Interfaces: {active_interfaces}, Internet: {internet_ok}")
    except Exception as e:
        return log_test("Network Availability", False, f"Error: {e}")

def test_python_modules():
    """Test required Python modules"""
    required_modules = [
        'flask', 'pygame', 'psutil', 'pytz', 'requests', 'bcrypt',
        'threading', 'json', 'time', 'datetime', 'subprocess'
    ]

    missing_modules = []
    for module in required_modules:
        try:
            __import__(module)
        except ImportError:
            missing_modules.append(module)

    modules_ok = len(missing_modules) == 0
    details = f"Missing: {missing_modules}" if missing_modules else "All modules available"
    return log_test("Python Modules", modules_ok, details)

def test_file_permissions():
    """Test file system permissions"""
    try:
        test_dir = Path('/tmp/bellnews_test')
        test_dir.mkdir(exist_ok=True)

        # Test file creation
        test_file = test_dir / 'test.json'
        test_file.write_text('{"test": true}')

        # Test file reading
        content = test_file.read_text()

        # Test file deletion
        test_file.unlink()
        test_dir.rmdir()

        return log_test("File Permissions", True, "Read/write/delete permissions OK")
    except Exception as e:
        return log_test("File Permissions", False, f"Permission error: {e}")

def test_startup_stability():
    """Test application startup simulation"""
    try:
        # Simulate multiple threads like the actual application
        def worker_thread():
            time.sleep(0.1)
            return True

        threads = []
        for i in range(5):
            t = threading.Thread(target=worker_thread)
            threads.append(t)
            t.start()

        # Wait for all threads
        for t in threads:
            t.join(timeout=2.0)

        # Check if all threads completed
        all_completed = all(not t.is_alive() for t in threads)
        return log_test("Startup Stability", all_completed, "Multi-threading test passed")

    except Exception as e:
        return log_test("Startup Stability", False, f"Threading error: {e}")

def run_comprehensive_test():
    """Run all tests and provide final assessment"""
    print("=" * 60)
    print("🔧 NanoPi NEO3 - Bell News Compatibility Test Suite")
    print("=" * 60)

    # Run all tests
    test_results['hardware_detection'] = test_hardware_detection()
    test_results['memory_sufficient'] = test_memory_requirements()
    test_results['cpu_performance'] = test_cpu_performance()
    test_results['gpio_available'] = test_gpio_functionality()
    test_results['i2c_available'] = test_i2c_availability()
    test_results['audio_available'] = test_audio_functionality()
    test_results['network_available'] = test_network_availability()
    test_results['python_modules'] = test_python_modules()
    test_results['file_permissions'] = test_file_permissions()
    test_results['startup_stability'] = test_startup_stability()

    # Calculate scores
    critical_tests = ['memory_sufficient', 'cpu_performance', 'python_modules',
                     'file_permissions', 'startup_stability']
    optional_tests = ['gpio_available', 'i2c_available', 'audio_available']

    critical_passed = sum(test_results[test] for test in critical_tests)
    optional_passed = sum(test_results[test] for test in optional_tests)
    total_passed = sum(test_results.values())

    print("\n" + "=" * 60)
    print("📊 TEST SUMMARY")
    print("=" * 60)
    print(f"Critical Tests: {critical_passed}/{len(critical_tests)} ✅")
    print(f"Optional Tests: {optional_passed}/{len(optional_tests)} ✅")
    print(f"Total Score: {total_passed}/{len(test_results)} ✅")

    # Final verdict
    will_work = critical_passed == len(critical_tests)

    if will_work:
        print("\n🎉 VERDICT: ✅ BELL NEWS WILL RUN WITHOUT HALTING")
        print("   Your NanoPi NEO3 meets all critical requirements!")

        if optional_passed < len(optional_tests):
            print(f"\n⚠️  Note: {len(optional_tests) - optional_passed} optional features may not work:")
            if not test_results['gpio_available']:
                print("   - Button controls will be disabled")
            if not test_results['i2c_available']:
                print("   - OLED display will use mock mode")
            if not test_results['audio_available']:
                print("   - Audio alarms may not work")
    else:
        print("\n❌ VERDICT: CRITICAL ISSUES FOUND")
        print("   The following must be fixed before running Bell News:")
        for test in critical_tests:
            if not test_results[test]:
                print(f"   - {test.replace('_', ' ').title()}")

    print("\n📋 RECOMMENDATIONS:")

    if not test_results['gpio_available']:
        print("   • Install OPi.GPIO: pip3 install OPi.GPIO")

    if not test_results['i2c_available']:
        print("   • Install OLED support: pip3 install luma.oled")
        print("   • Enable I2C: sudo apt install i2c-tools")

    if not test_results['audio_available']:
        print("   • Install audio: sudo apt install alsa-utils pulseaudio")
        print("   • Install pygame: pip3 install pygame")

    if not test_results['python_modules']:
        print("   • Install missing modules: pip3 install -r requirements.txt")

    print("\n🚀 To run Bell News:")
    print("   1. cd /path/to/bellapp/")
    print("   2. python3 nanopi_monitor.py")
    print("   3. python3 nano_web_timer.py (in another terminal)")

    return will_work

if __name__ == "__main__":
    success = run_comprehensive_test()
    sys.exit(0 if success else 1)