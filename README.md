# LPRTool

Push firmware or software to a list of printers using Windows `LPR`.

You give the tool a CSV of printer IP addresses and a firmware/software file. It builds a batch file that sends the file to every printer in the list. You then run that batch file.

This tool **builds** the batch file. It does **not** push anything by itself. You review the batch file and run it yourself.

## Versions

| Version | Path | Use when |
|---|---|---|
| v1 | `lprpowershell` | You want the proven legacy batch generator path with tightened IP validation. |
| v2 | `scripts/New-LprFirmwareBatch.ps1` | You want the newer source-first PowerShell workflow with dry-run default, manifest CSV, per-device error logging, and zip package output. |

**Current recommendation:** use v1 for any immediate real rollout unless v2 has passed a Windows dry run and small-device validation in your environment. v2 is the forward path for review, testing, and handoff.

---

## What you need before you start

1. **A Windows machine** with **LPR** enabled.
   - LPR is a Windows feature that is turned off by default.
   - To turn it on: **Settings → Apps → Optional features → Add a feature → search "LPR" → install**, or run this in an administrator command prompt:
     ```
     dism /online /enable-feature /featurename:Printing-Foundation-LPRPortMonitor
     ```
   - To check it is installed, open a command prompt and type `LPR`. If you see usage text, it is installed. If you see "not recognized," it is not.
2. **PowerShell** (already on Windows).
3. **A firmware or software file** to push (for example a `.dlm`, `.weblet`, `.rfu`, `.pkg`, `.hex`, or `.vme` file from the printer vendor).
4. **A CSV file** containing the printer IP addresses (see Step 1).

---

## Step 1 — Set up the CSV

Create a plain text file named something like `printers.csv`.

- The file must have **one printer IP address per line**.
- The tool reads the **first column only**. If your file has more columns, only the first is used.
- Do **not** include a header row. Just IPs.
- Blank lines are skipped.

Example `printers.csv`:
```
192.168.1.10
192.168.1.11
10.20.30.40
172.16.5.5
```

If your CSV comes from a spreadsheet and has extra columns, that is fine — just make sure the IP is the first column:
```
192.168.1.10,Building A, Floor 3
192.168.1.11,Building A, Floor 3
10.20.30.40,Building B
```

A ready-to-edit sample is included at `samples/printers.csv`. Replace the example IP addresses with the real printer IP addresses before generating a batch file.

---

## Step 2 — Run the tool to build the batch file

Open **PowerShell** and run the script. You need to provide four things:

| Parameter | What it is | Example |
|---|---|---|
| `-CsvPath` | Path to your CSV of IPs | `C:\push\printers.csv` |
| `-FirmwarePath` | Path to the firmware/software file | `C:\push\firmware.dlm` |
| `-OutputFolder` | Folder where the batch file will be created | `C:\push\output` |
| `-BatchFileName` | Name to give the generated batch file | `push_firmware` |

### Option A: Open the Python UI

If Python is installed, you can open a small desktop UI:

```
python lprtool_ui.py
```

Use the UI to choose the CSV, firmware/package file, output folder, batch file name, and LPR queue. The UI has two modes:

- **Dry run only** previews valid/invalid rows and sample commands, and writes nothing.
- **Write package** creates the `.bat`, manifest CSV, error-log stub, and zip package. This matches the v2 PowerShell `-SkipDryRun` / `-Execute` behavior.

The older `lprpy` launcher opens the same UI.

### Option B: Open the PowerShell GUI

On Windows, you can also open the PowerShell GUI:

```
.\scripts\LPRTool-GUI.ps1
```

The PowerShell GUI wraps the v2 script. Use **Dry Run** to preview without writing files, or **Write Package** to create the `.bat`, manifest CSV, error-log stub, and zip package.

`LPRBatchPSGUI` is kept as a compatibility launcher with the same GUI content. If your PowerShell setup does not run extensionless scripts directly, use `scripts\LPRTool-GUI.ps1`.

The GUI's **Copy Run Command** button copies the manual command you would run after reviewing the generated batch file, for example:

```
Set-Location -LiteralPath "C:\push\output"
cmd /c "push_firmware.bat >> push_firmware_Errors.txt 2>&1"
```

### Option C: Run PowerShell directly

v1 example:
```
.\lprpowershell -CsvPath C:\push\printers.csv -FirmwarePath C:\push\firmware.dlm -OutputFolder C:\push\output -BatchFileName push_firmware
```

v2 dry-run example:
```
.\scripts\New-LprFirmwareBatch.ps1 -CsvPath .\samples\printer_ips.v2.sample.csv -FirmwarePath C:\push\firmware.dlm -OutputFolder C:\push\output -BatchFileName push_firmware
```

v2 write-package example:
```
.\scripts\New-LprFirmwareBatch.ps1 -CsvPath C:\push\printers.csv -FirmwarePath C:\push\firmware.dlm -OutputFolder C:\push\output -BatchFileName push_firmware -SkipDryRun
```

For v2, put `-SkipDryRun` at the end of the command after the required paths and batch name. `-Execute` is an alias for the same thing, so these two commands both write the package:

```
.\scripts\New-LprFirmwareBatch.ps1 -CsvPath C:\push\printers.csv -FirmwarePath C:\push\firmware.dlm -OutputFolder C:\push\output -BatchFileName push_firmware -SkipDryRun
```

```
.\scripts\New-LprFirmwareBatch.ps1 -CsvPath C:\push\printers.csv -FirmwarePath C:\push\firmware.dlm -OutputFolder C:\push\output -BatchFileName push_firmware -Execute
```

If neither `-SkipDryRun` nor `-Execute` is included, v2 only previews the plan and writes nothing.

What v1 does:
1. Reads the IPs from the CSV.
2. Creates a file named `push_firmware.bat` in your output folder.
3. Creates an empty error-log file named `push_firmware_Errors.txt`.
4. Creates a zip named `push_firmware_package.zip` containing both.

What v2 adds:
1. Dry-run is the default, so you can preview without writing files.
2. Creates a manifest CSV showing valid and invalid rows.
3. Generates a simple reviewable batch with direct `LPR` commands.
4. Creates a zip package containing the batch, manifest, and error-log stub.

When it finishes, it prints the location of the batch file and a command to run it with error logging.

---

## Step 3 — Review and run the batch file

1. **Open the `.bat` file in Notepad and look at it.** You should see one line per printer:
   ```
   LPR -S 192.168.1.10 -P lp "C:\push\firmware.dlm"
   LPR -S 192.168.1.11 -P lp "C:\push\firmware.dlm"
   ...
   ```
   Confirm the IPs look right and the firmware path is correct.

2. **Open a command prompt as administrator.**

3. **Change to the output folder** and run the batch file, sending any errors to the error log:
   ```
   cd C:\push\output
   push_firmware.bat >> push_firmware_Errors.txt 2>&1
   ```
   The `>> push_firmware_Errors.txt 2>&1` part captures both normal output and errors into the error log so you can review what happened.

4. **Wait for it to finish.** For a long list of printers this can take a while, because each `LPR` command runs one after another.

---

## Step 4 — Optional: schedule the reviewed batch file with Windows Task Scheduler

Use Task Scheduler only after you have generated and reviewed the `.bat` file. The scheduled task should run the reviewed batch file, not the LPRTool generator.

1. **Confirm the output folder has everything the task needs.**
   - Example output folder: `C:\push\output`
   - Batch file: `C:\push\output\push_firmware.bat`
   - Error log: `C:\push\output\push_firmware_Errors.txt`
   - Firmware path inside the batch file still points to the correct firmware/software file.

2. **Open Task Scheduler.**
   - Press **Start**.
   - Search for **Task Scheduler**.
   - Right-click it and choose **Run as administrator**.

3. **Create the task.**
   - In the right-side **Actions** panel, select **Create Task...**.
   - On the **General** tab:
     - Name it something clear, such as `LPR Firmware Push`.
     - Select **Run whether user is logged on or not** if this must run unattended.
     - Select **Run with highest privileges**.
     - Choose a Windows account that has permission to read the firmware file and reach the printer network.

4. **Set the schedule.**
   - Open the **Triggers** tab.
   - Select **New...**.
   - Choose the date and time you want the push to run.
   - Select **OK**.

5. **Point the task at the batch file.**
   - Open the **Actions** tab.
   - Select **New...**.
   - Set **Action** to **Start a program**.
   - Set **Program/script** to:
     ```
     cmd.exe
     ```
   - Set **Add arguments** to:
     ```
     /c "push_firmware.bat >> push_firmware_Errors.txt 2>&1"
     ```
   - Set **Start in** to the output folder:
     ```
     C:\push\output
     ```
   - Select **OK**.

6. **Adjust power/network settings.**
   - Open the **Conditions** tab.
   - If this is a desktop or server, clear **Start the task only if the computer is on AC power** if that setting is not useful.
   - If the machine might be asleep, enable **Wake the computer to run this task**.
   - Make sure the machine will be on the same network/VPN that can reach the printers.

7. **Save and test the task.**
   - Select **OK** to save the task.
   - Enter the Windows account password if prompted.
   - In Task Scheduler Library, right-click the task and select **Run**.
   - After it finishes, open `push_firmware_Errors.txt` and confirm the output looks right.
   - If the test is only a dry run of scheduling, use a small CSV with one known test printer first.

For unattended tasks, avoid mapped drives like `Z:\firmware.dlm`. Scheduled tasks often cannot see mapped drives. Use a local path such as `C:\push\firmware.dlm` or a full UNC path such as `\\server\share\firmware.dlm`, and make sure the task account has access.

---

## Step 5 — If there are errors

Open `push_firmware_Errors.txt`. Each failed line tells you which printer failed and why.

**Common errors and fixes:**

| Error message | What it means | What to do |
|---|---|---|
| `'LPR' is not recognized` | LPR is not installed on this machine | Enable the LPR feature (see "What you need before you start"). |
| `Access is denied` | The command prompt is not running as administrator | Close it, right-click Command Prompt → **Run as administrator**, and try again. |
| `The system cannot find the file specified` | The firmware path in the batch file is wrong | Check that the firmware file exists at the path shown in each line. If you moved it, edit the batch file or re-run the tool with the correct `-FirmwarePath`. |
| `Printer on <IP> is not responding` / timeout | The printer is off, offline, or the IP is wrong | Confirm the printer is powered on and reachable (`ping <IP>`). Remove bad IPs from the CSV and re-run, or fix the IP and re-run that one line. |
| `LPR error: protocol error` | The printer rejected the file (wrong file type for that model, or the printer is mid-job) | Confirm the firmware file matches the printer model. Wait for the printer to finish any current jobs and retry. |

**To re-run only the printers that failed:**
1. Open the error log and copy the IPs that failed.
2. Put just those IPs into a new CSV (for example, `retry.csv`).
3. Run the tool again pointing at `retry.csv`, with a new batch file name (for example, `retry_firmware`).

---

## Notes

- **The tool does not push anything.** It only builds the batch file. You run the batch file yourself, after reviewing it.
- **One IP per line, first column only.** Extra columns and blank lines are ignored.
- **Invalid IP addresses are skipped.** Lines that are not valid IP addresses (for example `999.1.1.1` or a hostname) are left out of the batch file.
- **Run the batch file from a machine that can reach the printers.** If the printers are on a network the build machine cannot access, the push will fail.

## v2 Tests

If Pester is installed on Windows:

```
Invoke-Pester .\tests\New-LprFirmwareBatch.Tests.ps1 -Output Detailed
```

The main regression covered is strict IPv4 validation. Invalid octets such as `999.1.1.1`, `256.0.0.1`, and `1.2.3.300` must be rejected.
