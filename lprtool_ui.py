import csv
import os
import re
import zipfile
from datetime import datetime


VALID_IP_PATTERN = re.compile(r"^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$")
PACKAGE_EXTENSIONS = "*.dlm *.weblet *.rfu *.pkg *.hex *.vme *.*"
tk = None
filedialog = None
messagebox = None
ttk = None


def is_valid_ip(candidate):
    if not candidate or not candidate.strip():
        return False
    candidate = candidate.strip()
    if not VALID_IP_PATTERN.match(candidate):
        return False
    return all(0 <= int(octet) <= 255 for octet in candidate.split("."))


def detect_file_type(file_path):
    ext = os.path.splitext(file_path.lower())[1]
    if ext == ".dlm":
        try:
            size_mb = os.path.getsize(file_path) / (1024 * 1024)
        except OSError:
            size_mb = 0
        return "DLM Firmware" if size_mb > 50 else "DLM Patch/Clone"
    if ext == ".weblet":
        return "Weblet Package"
    if ext == ".rfu":
        return "RFU Firmware"
    if ext == ".pkg":
        return "Package File"
    if ext in {".hex", ".vme"}:
        return "Firmware File"
    return "Unknown"


def read_device_rows(csv_path):
    records = []
    with open(csv_path, newline="", encoding="utf-8-sig") as handle:
        reader = csv.reader(handle)
        for row in reader:
            if not row:
                continue
            ip = row[0].strip().strip('"')
            if not ip:
                records.append({"Ip": "", "Status": "Skipped", "Message": "Blank first column."})
            elif is_valid_ip(ip):
                records.append({"Ip": ip, "Status": "Valid", "Message": ""})
            else:
                records.append(
                    {
                        "Ip": ip,
                        "Status": "Invalid",
                        "Message": "Not a valid IPv4 address; each octet must be 0-255.",
                    }
                )
    return records


def ensure_batch_name(batch_file_name):
    return batch_file_name if batch_file_name.lower().endswith(".bat") else f"{batch_file_name}.bat"


def build_batch_lines(valid_ips, firmware_path, lpr_queue, error_log_name, total_count):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    header = [
        "REM ============================================================================",
        "REM LPRTool generated firmware push batch",
        f"REM Generated : {timestamp}",
        f"REM Firmware  : {firmware_path}",
        f"REM Devices   : {len(valid_ips)} valid IP(s) out of {total_count} row(s)",
        f"REM Queue     : {lpr_queue}",
        "REM Review each line before running.",
        "REM ============================================================================",
        "",
    ]
    commands = []
    for ip in valid_ips:
        commands.append(f'LPR -S {ip} -P {lpr_queue} "{firmware_path}"')
    return header + commands


def write_manifest(manifest_path, records):
    with open(manifest_path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["Ip", "Status", "Message"])
        writer.writeheader()
        writer.writerows(records)


def create_package(csv_path, firmware_path, output_folder, batch_file_name, lpr_queue):
    records = read_device_rows(csv_path)
    valid_ips = [record["Ip"] for record in records if record["Status"] == "Valid"]
    invalid_count = len([record for record in records if record["Status"] == "Invalid"])
    skipped_count = len([record for record in records if record["Status"] == "Skipped"])

    batch_file_name = ensure_batch_name(batch_file_name)
    base_name = os.path.splitext(batch_file_name)[0]
    batch_path = os.path.join(output_folder, batch_file_name)
    error_log_name = f"{base_name}_Errors.txt"
    error_log_path = os.path.join(output_folder, error_log_name)
    manifest_path = os.path.join(output_folder, f"{base_name}_manifest.csv")
    zip_path = os.path.join(output_folder, f"{base_name}_package.zip")

    if not valid_ips:
        return {
            "ok": False,
            "message": "No valid IP addresses found. Nothing was written.",
            "records": records,
        }

    os.makedirs(output_folder, exist_ok=True)
    lines = build_batch_lines(valid_ips, firmware_path, lpr_queue, error_log_name, len(records))

    with open(batch_path, "w", encoding="ascii", newline="\r\n") as handle:
        handle.write("\n".join(lines))

    write_manifest(manifest_path, records)
    open(error_log_path, "a", encoding="utf-8").close()

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.write(batch_path, os.path.basename(batch_path))
        archive.write(manifest_path, os.path.basename(manifest_path))
        archive.write(error_log_path, os.path.basename(error_log_path))

    return {
        "ok": True,
        "batch_path": batch_path,
        "manifest_path": manifest_path,
        "error_log_path": error_log_path,
        "zip_path": zip_path,
        "valid_count": len(valid_ips),
        "invalid_count": invalid_count,
        "skipped_count": skipped_count,
        "records": records,
    }


class LprToolUi:
    def __init__(self, root):
        self.root = root
        self.root.title("LPRTool")
        self.root.geometry("720x640")
        self.file_type = tk.StringVar(value="Package type: unknown")
        self.mode = tk.StringVar(value="dry_run")
        self.output_text = tk.StringVar(value="")

        self.csv_path = tk.StringVar(value="")
        self.firmware_path = tk.StringVar(value="")
        self.output_folder = tk.StringVar(value="")
        self.batch_name = tk.StringVar(value="push_firmware")
        self.lpr_queue = tk.StringVar(value="lp")
        self.last_run_command = ""

        self.build()

    def build(self):
        frame = ttk.Frame(self.root, padding=14)
        frame.pack(fill=tk.BOTH, expand=True)

        ttk.Label(frame, text="CSV of printer IPs").grid(row=0, column=0, sticky="w")
        ttk.Entry(frame, textvariable=self.csv_path, width=72).grid(row=1, column=0, sticky="ew")
        ttk.Button(frame, text="Browse", command=self.browse_csv).grid(row=1, column=1, padx=(8, 0))

        ttk.Label(frame, text="Firmware or package file").grid(row=2, column=0, sticky="w", pady=(12, 0))
        ttk.Entry(frame, textvariable=self.firmware_path, width=72).grid(row=3, column=0, sticky="ew")
        ttk.Button(frame, text="Browse", command=self.browse_package).grid(row=3, column=1, padx=(8, 0))
        ttk.Label(frame, textvariable=self.file_type).grid(row=4, column=0, sticky="w")

        ttk.Label(frame, text="Output folder").grid(row=5, column=0, sticky="w", pady=(12, 0))
        ttk.Entry(frame, textvariable=self.output_folder, width=72).grid(row=6, column=0, sticky="ew")
        ttk.Button(frame, text="Choose", command=self.choose_output).grid(row=6, column=1, padx=(8, 0))

        settings = ttk.Frame(frame)
        settings.grid(row=7, column=0, columnspan=2, sticky="ew", pady=(12, 0))
        ttk.Label(settings, text="Batch file name").grid(row=0, column=0, sticky="w")
        ttk.Entry(settings, textvariable=self.batch_name, width=28).grid(row=1, column=0, sticky="w")
        ttk.Label(settings, text="LPR queue").grid(row=0, column=1, sticky="w", padx=(18, 0))
        ttk.Entry(settings, textvariable=self.lpr_queue, width=14).grid(row=1, column=1, sticky="w", padx=(18, 0))

        mode_box = ttk.LabelFrame(frame, text="Mode")
        mode_box.grid(row=8, column=0, columnspan=2, sticky="ew", pady=(14, 0))
        ttk.Radiobutton(mode_box, text="Dry run only - preview and write nothing", variable=self.mode, value="dry_run").pack(
            anchor="w", padx=8, pady=(6, 0)
        )
        ttk.Radiobutton(
            mode_box,
            text="Write package - same as PowerShell -SkipDryRun / -Execute",
            variable=self.mode,
            value="write",
        ).pack(anchor="w", padx=8, pady=(0, 6))

        buttons = ttk.Frame(frame)
        buttons.grid(row=9, column=0, columnspan=2, sticky="ew", pady=(14, 0))
        ttk.Button(buttons, text="Preview / Generate", command=self.run).pack(side=tk.LEFT)
        ttk.Button(buttons, text="Copy Run Command", command=self.copy_run_command).pack(side=tk.LEFT, padx=(8, 0))

        output = ttk.LabelFrame(frame, text="Output")
        output.grid(row=10, column=0, columnspan=2, sticky="nsew", pady=(14, 0))
        self.output_widget = tk.Text(output, wrap="word", height=16)
        self.output_widget.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)

        frame.columnconfigure(0, weight=1)
        frame.rowconfigure(10, weight=1)

    def browse_csv(self):
        path = filedialog.askopenfilename(filetypes=[("CSV files", "*.csv"), ("All files", "*.*")])
        if path:
            self.csv_path.set(path)

    def browse_package(self):
        path = filedialog.askopenfilename(filetypes=[("Firmware/package files", PACKAGE_EXTENSIONS), ("All files", "*.*")])
        if path:
            self.firmware_path.set(path)
            self.file_type.set(f"Package type: {detect_file_type(path)}")

    def choose_output(self):
        path = filedialog.askdirectory()
        if path:
            self.output_folder.set(path)

    def validate(self):
        required = {
            "CSV path": self.csv_path.get(),
            "Firmware/package path": self.firmware_path.get(),
            "Output folder": self.output_folder.get(),
            "Batch file name": self.batch_name.get(),
            "LPR queue": self.lpr_queue.get(),
        }
        missing = [name for name, value in required.items() if not value.strip()]
        if missing:
            messagebox.showerror("Missing information", "Missing: " + ", ".join(missing))
            return False
        if not os.path.exists(self.csv_path.get()):
            messagebox.showerror("Missing file", f"CSV file not found:\n{self.csv_path.get()}")
            return False
        if not os.path.exists(self.firmware_path.get()):
            messagebox.showerror("Missing file", f"Firmware/package file not found:\n{self.firmware_path.get()}")
            return False
        return True

    def run(self):
        if not self.validate():
            return

        try:
            records = read_device_rows(self.csv_path.get())
            valid = [record for record in records if record["Status"] == "Valid"]
            invalid = [record for record in records if record["Status"] == "Invalid"]
            skipped = [record for record in records if record["Status"] == "Skipped"]

            if self.mode.get() == "dry_run":
                message = self.build_preview(records, valid, invalid, skipped)
                self.set_output(message)
                return

            result = create_package(
                self.csv_path.get(),
                os.path.abspath(self.firmware_path.get()),
                self.output_folder.get(),
                self.batch_name.get(),
                self.lpr_queue.get(),
            )
            if not result["ok"]:
                self.set_output(result["message"])
                messagebox.showwarning("Nothing written", result["message"])
                return

            message = (
                "Package written.\n\n"
                f"Valid IPs: {result['valid_count']}\n"
                f"Invalid rows: {result['invalid_count']}\n"
                f"Skipped rows: {result['skipped_count']}\n\n"
                f"Batch: {result['batch_path']}\n"
                f"Manifest: {result['manifest_path']}\n"
                f"Error log: {result['error_log_path']}\n"
                f"Zip: {result['zip_path']}\n\n"
                "Review the generated .bat before running it.\n\n"
                f"Manual run command:\n{self.manual_run_command()}"
            )
            self.set_output(message)
            messagebox.showinfo("Package written", message)
        except Exception as exc:
            messagebox.showerror("Error", str(exc))

    def build_preview(self, records, valid, invalid, skipped):
        batch_file_name = ensure_batch_name(self.batch_name.get())
        lines = [
            "Dry run only. No files were written.",
            "",
            f"CSV: {self.csv_path.get()}",
            f"Package: {os.path.abspath(self.firmware_path.get())} ({detect_file_type(self.firmware_path.get())})",
            f"Output folder: {self.output_folder.get()}",
            f"Batch file: {batch_file_name}",
            f"LPR queue: {self.lpr_queue.get()}",
            "",
            f"Rows read: {len(records)}",
            f"Valid IPs: {len(valid)}",
            f"Invalid rows: {len(invalid)}",
            f"Skipped rows: {len(skipped)}",
        ]
        if valid:
            lines.extend(["", "Sample commands:"])
            for record in valid[:5]:
                lines.append(f'LPR -S {record["Ip"]} -P {self.lpr_queue.get()} "{os.path.abspath(self.firmware_path.get())}"')
        if invalid:
            lines.extend(["", "Invalid rows:"])
            for record in invalid[:10]:
                lines.append(f'{record["Ip"]}: {record["Message"]}')
        lines.extend(["", "Choose Write package to create the .bat, manifest, error-log stub, and zip."])
        lines.extend(["", "Manual run command after writing the package:", self.manual_run_command()])
        return "\n".join(lines)

    def set_output(self, message):
        self.output_widget.delete("1.0", tk.END)
        self.output_widget.insert(tk.END, message)

    def manual_run_command(self):
        batch_file_name = ensure_batch_name(self.batch_name.get())
        base_name = os.path.splitext(batch_file_name)[0]
        error_log_name = f"{base_name}_Errors.txt"
        output_folder = self.output_folder.get()
        return f'Set-Location -LiteralPath "{output_folder}"\ncmd /c "{batch_file_name} >> {error_log_name} 2>&1"'

    def copy_run_command(self):
        if not self.output_folder.get().strip() or not self.batch_name.get().strip():
            messagebox.showerror("Missing information", "Output folder and batch file name are required.")
            return
        text = self.manual_run_command()
        self.root.clipboard_clear()
        self.root.clipboard_append(text)
        self.root.update()
        self.set_output(f"Copied manual run command:\n{text}")


def main():
    global tk, filedialog, messagebox, ttk
    import tkinter as tk
    from tkinter import filedialog, messagebox, ttk

    root = tk.Tk()
    LprToolUi(root)
    root.mainloop()


if __name__ == "__main__":
    main()
