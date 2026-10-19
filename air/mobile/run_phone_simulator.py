"""Install and launch the prepared connected app in Apple's iPhone simulator."""
import argparse
import json
import subprocess
from run_phone import BUILD

NAME = "Ekoloko — iPhone 14 Pro Max"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-14-Pro-Max"

def command(*args):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshots", action="store_true", help="Enable expensive per-interaction review captures; leave off for play testing")
    args = parser.parse_args()
    app = BUILD / "apple-simulator/Payload/EkolokoPhoneReview.app"
    if not app.is_dir():
        raise SystemExit("Run package_phone_simulator.py first.")
    devices = json.loads(command("list", "devices", "available", "-j"))["devices"].get(RUNTIME, [])
    device = next((d for d in devices if d["name"] == NAME), None)
    if device is None:
        device = {"udid": command("create", NAME, DEVICE_TYPE, RUNTIME).strip(), "state": "Shutdown"}
    identifier = device["udid"]
    if device["state"] != "Booted":
        command("boot", identifier)
    command("bootstatus", identifier, "-b")
    command("install", identifier, str(app))
    launch_args = ["--mobile-snapshot"] if args.snapshots else []
    print(command("launch", "--terminate-running-process", identifier, "org.ekoloko.mobilephone", *launch_args))
    print("Automatic review captures: " + ("enabled" if args.snapshots else "disabled"))
    print("Open Xcode Device Hub and select " + NAME + ". Launch alone is not a passed runtime test.")

if __name__ == "__main__":
    main()
