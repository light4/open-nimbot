#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["bleak>=0.22", "pillow>=10"]
# ///
"""Find and connect to a NIMBOT BLE printer."""

import argparse
import asyncio

from bleak import BleakClient, BleakScanner
from bleak.exc import BleakError
from PIL import Image, ImageDraw, ImageFont

DEFAULT_NAME = "B1-G801041103"
NIMBOT_CHARACTERISTIC = "bef8d6c9-9c21-4c9e-b632-bd58c1009f9f"


def packet(command: int, data: bytes = b"") -> bytes:
    """Encode a NIMBOT command packet."""
    checksum = command ^ len(data)
    for byte in data:
        checksum ^= byte
    return bytes((0x55, 0x55, command, len(data), *data, checksum, 0xAA, 0xAA))


def parser() -> argparse.ArgumentParser:
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument(
        "--name",
        default=DEFAULT_NAME,
        help=f"advertised printer name (default: {DEFAULT_NAME})",
    )
    cli.add_argument(
        "--list", action="store_true", help="list nearby BLE devices and exit"
    )
    cli.add_argument(
        "--timeout",
        type=float,
        default=10,
        help="scan timeout in seconds (default: 10)",
    )
    cli.add_argument(
        "--hold",
        type=float,
        default=10,
        help="keep the connection open in seconds (default: 10)",
    )
    cli.add_argument(
        "--test-label",
        action="store_true",
        help="print a small NIMBOT / BLE OK test label",
    )
    cli.add_argument("--text", help="print text (supports multiple lines)")
    cli.add_argument(
        "--self-check", action="store_true", help="run an offline sanity check and exit"
    )
    return cli


async def print_text(client: BleakClient, text: str) -> None:
    """Print text with the B1's V4 raster protocol."""
    width = 160
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Hiragino Sans GB.ttc", 24)
    except OSError:
        font = ImageFont.load_default(size=24)
    height = max(80, 20 + 34 * len(text.splitlines()))
    image = Image.new("1", (width, height), 1)
    ImageDraw.Draw(image).multiline_text((12, 12), text, fill=0, font=font, spacing=5)
    await client.write_gatt_char(NIMBOT_CHARACTERISTIC, packet(0x21, b"\x03"), True)
    await client.write_gatt_char(NIMBOT_CHARACTERISTIC, packet(0x23, b"\x01"), True)
    await client.write_gatt_char(
        NIMBOT_CHARACTERISTIC, packet(0x01, b"\x00\x01\0\0\0\0\0"), True
    )
    await client.write_gatt_char(NIMBOT_CHARACTERISTIC, packet(0x03, b"\x01"), True)
    await client.write_gatt_char(
        NIMBOT_CHARACTERISTIC,
        packet(0x13, height.to_bytes(2, "big") + width.to_bytes(2, "big") + b"\0\x01"),
        True,
    )
    for y in range(height):
        row = bytes(
            sum((image.getpixel((x + bit, y)) == 0) << (7 - bit) for bit in range(8))
            for x in range(0, width, 8)
        )
        if any(row):
            counts = bytes(
                (
                    sum(byte.bit_count() for byte in row[:16]),
                    sum(byte.bit_count() for byte in row[16:]),
                    0,
                )
            )
            command, payload = 0x85, y.to_bytes(2, "big") + counts + b"\x01" + row
        else:
            command, payload = 0x84, y.to_bytes(2, "big") + b"\x01"
        await client.write_gatt_char(
            NIMBOT_CHARACTERISTIC, packet(command, payload), y % 10 == 9
        )
    await client.write_gatt_char(NIMBOT_CHARACTERISTIC, packet(0xE3, b"\x01"), True)
    await asyncio.sleep(3)
    await client.write_gatt_char(NIMBOT_CHARACTERISTIC, packet(0xF3, b"\x01"), True)


async def run(args: argparse.Namespace) -> int:
    devices = await BleakScanner.discover(timeout=args.timeout)
    if args.list:
        for device in devices:
            print(f"{device.name or '<unnamed>'}\t{device.address}")
        return 0

    device = next((item for item in devices if item.name == args.name), None)
    if device is None:
        print(
            f"Printer {args.name!r} was not found. Turn it on and run: uv run nimbot_connect.py --list"
        )
        return 1

    print(f"Connecting to {device.name} ({device.address})…")
    async with BleakClient(device, timeout=args.timeout) as client:
        print("Connected.")
        for service in client.services:
            print(f"  service {service.uuid}")
            for characteristic in service.characteristics:
                print(
                    f"    {characteristic.uuid} [{','.join(characteristic.properties)}]"
                )
        if args.test_label or args.text:
            text = args.text or "NIMBOT\nBLE OK"
            print(f"Sending a {text!r} label…")
            await print_text(client, text)
            print("Label sent.")
        if args.hold:
            print(f"Keeping connection open for {args.hold:g} seconds…")
            await asyncio.sleep(args.hold)
    print("Disconnected.")
    return 0


def main() -> int:
    args = parser().parse_args()
    if args.self_check:
        assert parser().parse_args([]).name == DEFAULT_NAME
        assert parser().parse_args(["--hold", "0"]).hold == 0
        assert parser().parse_args(["--text", "测试"]).text == "测试"
        assert packet(0x01, b"\x00\x01\0\0\0\0\0") == bytes.fromhex(
            "55 55 01 07 00 01 00 00 00 00 00 07 aa aa"
        )
        print("OK")
        return 0
    if args.timeout <= 0 or args.hold < 0:
        parser().error("--timeout must be positive and --hold cannot be negative")
    try:
        return asyncio.run(run(args))
    except (BleakError, OSError) as error:
        print(f"Bluetooth error: {error}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
