#!/usr/bin/env python3
"""
Health Check Script for NanoPi NEO Docker Services
This script monitors the health of your Docker containers and provides diagnostics.
"""

import subprocess
import json
import requests
import time
import sys
from datetime import datetime

def run_command(cmd):
    """Execute a shell command and return the output."""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        return result.returncode == 0, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return False, "", "Command timed out"
    except Exception as e:
        return False, "", str(e)

def check_docker_containers():
    """Check the status of Docker containers."""
    print("🐳 Checking Docker containers...")
    success, stdout, stderr = run_command("docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'")
    
    if success:
        print(stdout)
        # Check if all expected containers are running
        expected_containers = ['bellapp', 'newsapp', 'config_service']
        running_containers = []
        
        for line in stdout.split('\n')[1:]:  # Skip header
            if line.strip():
                container_name = line.split('\t')[0]
                if container_name in expected_containers:
                    running_containers.append(container_name)
        
        missing = set(expected_containers) - set(running_containers)
        if missing:
            print(f"❌ Missing containers: {', '.join(missing)}")
            return False
        else:
            print("✅ All expected containers are running")
            return True
    else:
        print(f"❌ Failed to check containers: {stderr}")
        return False

def check_network_connectivity():
    """Check network connectivity and IP configuration."""
    print("\n🌐 Checking network connectivity...")
    
    # Get current IP
    success, ip_output, _ = run_command("hostname -I")
    if success:
        ips = ip_output.strip().split()
        main_ip = ips[0] if ips else "Unknown"
        print(f"📍 Current IP addresses: {' '.join(ips)}")
        print(f"🎯 Primary IP: {main_ip}")
    else:
        print("❌ Could not determine IP address")
        main_ip = "192.168.33.3"  # Fallback
    
    return main_ip

def check_service_endpoints(ip_address):
    """Check if service endpoints are responding."""
    print(f"\n🔍 Checking service endpoints on {ip_address}...")
    
    services = {
        'BellApp (Python)': f'http://{ip_address}:5000',
        'NewsApp (Laravel)': f'http://{ip_address}:8000',
        'Config Service': f'http://{ip_address}:5002',
        'Laravel API - News': f'http://{ip_address}:8000/api/news',
        'Laravel API - Settings': f'http://{ip_address}:8000/api/settings'
    }
    
    results = {}
    for service_name, url in services.items():
        try:
            response = requests.get(url, timeout=5)
            if response.status_code < 400:
                print(f"✅ {service_name}: OK ({response.status_code})")
                results[service_name] = True
            else:
                print(f"⚠️ {service_name}: HTTP {response.status_code}")
                results[service_name] = False
        except requests.exceptions.RequestException as e:
            print(f"❌ {service_name}: Connection failed - {str(e)[:60]}...")
            results[service_name] = False
    
    return results

def check_log_files():
    """Check recent log entries for errors."""
    print("\n📋 Checking recent log entries...")
    
    # Check Docker logs for each container
    containers = ['bellapp', 'newsapp', 'config_service']
    for container in containers:
        print(f"\n📝 Recent logs for {container}:")
        success, logs, _ = run_command(f"docker logs --tail 3 {container}")
        if success:
            for line in logs.split('\n')[-3:]:
                if line.strip():
                    print(f"   {line}")
        else:
            print(f"   ❌ Could not retrieve logs for {container}")

def generate_report():
    """Generate a comprehensive health report."""
    print("=" * 60)
    print(f"🏥 NanoPi NEO Health Check Report")
    print(f"📅 Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)
    
    # Check Docker containers
    docker_ok = check_docker_containers()
    
    # Check network
    main_ip = check_network_connectivity()
    
    # Check service endpoints
    service_results = check_service_endpoints(main_ip)
    
    # Check logs
    check_log_files()
    
    # Summary
    print("\n" + "=" * 60)
    print("📊 SUMMARY")
    print("=" * 60)
    
    if docker_ok:
        print("✅ Docker containers: All running")
    else:
        print("❌ Docker containers: Issues detected")
    
    healthy_services = sum(1 for result in service_results.values() if result)
    total_services = len(service_results)
    print(f"🌐 Service endpoints: {healthy_services}/{total_services} healthy")
    
    if docker_ok and healthy_services == total_services:
        print("🎉 Overall status: HEALTHY")
        return 0
    else:
        print("⚠️ Overall status: ISSUES DETECTED")
        return 1

def main():
    """Main function."""
    if len(sys.argv) > 1 and sys.argv[1] == "--continuous":
        print("🔄 Running in continuous mode (Ctrl+C to stop)")
        try:
            while True:
                generate_report()
                print(f"\n⏰ Next check in 60 seconds...")
                time.sleep(60)
        except KeyboardInterrupt:
            print("\n🛑 Continuous monitoring stopped.")
    else:
        exit_code = generate_report()
        sys.exit(exit_code)

if __name__ == "__main__":
    main()