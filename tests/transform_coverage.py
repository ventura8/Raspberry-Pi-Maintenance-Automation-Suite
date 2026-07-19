import xml.etree.ElementTree as ET
import sys
import os
import argparse
import subprocess


def compute_lizard_complexity_map(filenames):
    existing = [name for name in filenames if name and os.path.exists(name)]
    if not existing:
        return {}

    try:
        result = subprocess.run(
            [sys.executable, "-m", "lizard", "-X", *existing],
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        try:
            result = subprocess.run(
                ["lizard", "-X", *existing],
                check=True,
                capture_output=True,
                text=True,
            )
        except (subprocess.CalledProcessError, FileNotFoundError):
            return {}

    try:
        lizard_root = ET.fromstring(result.stdout)
    except ET.ParseError:
        return {}

    file_measure = None
    for measure in lizard_root.findall("measure"):
        if measure.get("type") == "File":
            file_measure = measure
            break

    if file_measure is None:
        return {}

    complexity_by_file = {}
    for item in file_measure.findall("item"):
        name = item.get("name")
        values = [v.text for v in item.findall("value")]
        if not name or len(values) < 4:
            continue

        # File measure item values are: Nr, NCSS, CCN(sum), Functions
        try:
            ccn_sum = float(values[2] or 0)
            func_count = int(float(values[3] or 0))
        except ValueError:
            continue

        avg_ccn = ccn_sum / func_count if func_count > 0 else 1.0
        complexity_by_file[name] = max(1.0, avg_ccn)

    return complexity_by_file

def generate_badge(line_rate, output_path="assets/coverage.svg"):
    try:
        coverage = float(line_rate) * 100
    except ValueError:
        coverage = 0.0

    color = "#e05d44" # red
    if coverage >= 95:
        color = "#4c1" # brightgreen
    elif coverage >= 90:
         color = "#97ca00" # green
    elif coverage >= 75:
        color = "#dfb317" # yellow
    elif coverage >= 50:
        color = "#fe7d37" # orange

    coverage_str = f"{int(coverage)}%"

    label_text = "Coverage"
    value_text = coverage_str

    # Estimate widths
    label_width = 61 
    value_width = int(len(value_text) * 8.5) + 10 

    total_width = label_width + value_width

    # Center positions
    label_x = label_width / 2.0 * 10
    value_x = (label_width + value_width / 2.0) * 10

    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{total_width}" height="20" role="img" aria-label="{label_text}: {value_text}">
    <title>{label_text}: {value_text}</title>
    <linearGradient id="s" x2="0" y2="100%">
        <stop offset="0" stop-color="#bbb" stop-opacity=".1"/>
        <stop offset="1" stop-opacity=".1"/>
    </linearGradient>
    <clipPath id="r">
        <rect width="{total_width}" height="20" rx="3" fill="#fff"/>
    </clipPath>
    <g clip-path="url(#r)">
        <rect width="{label_width}" height="20" fill="#555"/>
        <rect x="{label_width}" width="{value_width}" height="20" fill="{color}"/>
        <rect width="{total_width}" height="20" fill="url(#s)"/>
    </g>
    <g fill="#fff" text-anchor="middle" font-family="Verdana,Geneva,DejaVu Sans,sans-serif" text-rendering="geometricPrecision" font-size="110">
        <text aria-hidden="true" x="{int(label_x)}" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="{label_width*10 - 100}">{label_text}</text>
        <text x="{int(label_x)}" y="140" transform="scale(.1)" fill="#fff" textLength="{label_width*10 - 100}">{label_text}</text>
        <text aria-hidden="true" x="{int(value_x)}" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="{value_width*10 - 100}">{value_text}</text>
        <text x="{int(value_x)}" y="140" transform="scale(.1)" fill="#fff" textLength="{value_width*10 - 100}">{value_text}</text>
    </g>
</svg>"""

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    
    with open(output_path, "w") as f:
        f.write(svg)
    print(f"Generated badge: {output_path} ({coverage_str})")

def transform_coverage(
    xml_file,
    fail_under=None,
    fail_under_per_file=None,
    max_complexity_overall=None,
    max_complexity_per_file=None,
    require_real_complexity=False,
):
    if not os.path.exists(xml_file):
        print(f"Error: {xml_file} not found")
        sys.exit(1)

    try:
        tree = ET.parse(xml_file)
        root = tree.getroot()
        
        root_line_rate = root.get("line-rate", "0")
        root_complexity = root.get("complexity", "0")
        generate_badge(root_line_rate)

    except ET.ParseError as e:
        print(f"Error parsing XML: {e}")
        sys.exit(1)

    packages_el = root.find('packages')
    if packages_el is None:
        print("No <packages> element found")
        sys.exit(1)

    all_classes = []
    for pkg in packages_el.findall('package'):
        classes_el = pkg.find('classes')
        if classes_el is not None:
            all_classes.extend(classes_el.findall('class'))

    packages_el.clear()

    class_filenames = [cls.get("filename", "") for cls in all_classes]
    lizard_complexity = compute_lizard_complexity_map(class_filenames)

    if require_real_complexity and not lizard_complexity:
        print(
            "Error: lizard complexity data is unavailable. "
            "Install lizard in this environment before generating coverage summary."
        )
        sys.exit(1)

    if lizard_complexity:
        root_complexity = str(max(lizard_complexity.values()))
        root.set("complexity", root_complexity)

    for cls in all_classes:
        filename = cls.get('filename')
        pkg_name = filename 
        
        new_pkg = ET.SubElement(packages_el, 'package')
        new_pkg.set('name', pkg_name)
        
        for attr in ['line-rate', 'branch-rate', 'complexity']:
            if attr == 'complexity' and filename in lizard_complexity:
                val = f"{lizard_complexity[filename]:.2f}"
                cls.set('complexity', val)
                new_pkg.set(attr, val)
            elif val := cls.get(attr):
                new_pkg.set(attr, val)
            else:
                new_pkg.set(attr, '0.0')

        new_classes = ET.SubElement(new_pkg, 'classes')
        new_classes.append(cls)

    tree.write(xml_file, encoding='UTF-8', xml_declaration=True)
    print(f"Successfully transformed {xml_file}: Split {len(all_classes)} classes into separate packages.")
    
    generate_markdown_summary(all_classes, root_line_rate, root_complexity)

    if fail_under is not None:
        try:
            current_pct = float(root_line_rate) * 100
            if current_pct < fail_under:
                print(f"❌ Coverage is {current_pct:.2f}%, which is below the minimum required {fail_under}%")
                sys.exit(1)
            else:
                print(f"✅ Coverage is {current_pct:.2f}%, meeting the minimum {fail_under}% requirement.")
        except ValueError:
            print("Error calculating coverage percentage for threshold check.")
            sys.exit(1)

    if fail_under_per_file is not None:
        offenders = []
        for cls in all_classes:
            filename = cls.get("filename", "unknown")
            line_rate = cls.get("line-rate", "0")
            try:
                pct = float(line_rate) * 100
            except ValueError:
                pct = 0.0

            if pct < fail_under_per_file:
                offenders.append((filename, pct))

        if offenders:
            print(
                f"❌ Per-file coverage gate failed: {len(offenders)} file(s) below {fail_under_per_file:.2f}%"
            )
            for filename, pct in sorted(offenders, key=lambda item: item[1]):
                print(f"   - {filename}: {pct:.2f}%")
            sys.exit(1)
        else:
            print(
                f"✅ Per-file coverage gate passed: all files are >= {fail_under_per_file:.2f}%"
            )

    if max_complexity_overall is not None:
        try:
            overall_cplx = float(root_complexity)
        except ValueError:
            overall_cplx = 0.0

        if overall_cplx > max_complexity_overall:
            print(
                f"❌ Overall complexity gate failed: {overall_cplx:.2f} exceeds max {max_complexity_overall:.2f}"
            )
            sys.exit(1)
        else:
            print(
                f"✅ Overall complexity gate passed: {overall_cplx:.2f} <= {max_complexity_overall:.2f}"
            )

    if max_complexity_per_file is not None:
        offenders = []
        for cls in all_classes:
            filename = cls.get("filename", "unknown")
            complexity = cls.get("complexity", "0")
            try:
                cplx = float(complexity)
            except ValueError:
                cplx = 0.0

            if cplx > max_complexity_per_file:
                offenders.append((filename, cplx))

        if offenders:
            print(
                f"❌ Per-file complexity gate failed: {len(offenders)} file(s) above {max_complexity_per_file:.2f}"
            )
            for filename, cplx in sorted(offenders, key=lambda item: item[1], reverse=True):
                print(f"   - {filename}: {cplx:.2f}")
            sys.exit(1)
        else:
            print(
                f"✅ Per-file complexity gate passed: all files are <= {max_complexity_per_file:.2f}"
            )

def generate_markdown_summary(classes, overall_rate, overall_complexity, output_path="code-coverage-results.md"):
    try:
        overall_pct = float(overall_rate) * 100
    except ValueError:
        overall_pct = 0.0

    try:
        overall_cplx = float(overall_complexity)
    except ValueError:
        overall_cplx = 0.0

    md_lines = []
    md_lines.append(f"## Code Coverage and Complexity Summary")
    md_lines.append(f"")
    md_lines.append(f"**Overall Coverage:** {overall_pct:.2f}%")
    md_lines.append(f"**Overall Complexity:** {overall_cplx:.2f}")
    md_lines.append(f"")
    md_lines.append("> Complexity is computed via lizard (average CCN per function in each file).")
    md_lines.append(f"")
    md_lines.append(f"| File | Coverage | Complexity | Missing Lines |")
    md_lines.append(f"| :--- | :---: | :---: | :--- |")

    for cls in sorted(classes, key=lambda item: item.get('filename', '')):
        filename = cls.get('filename')
        line_rate = cls.get('line-rate', '0')
        complexity = cls.get('complexity', '0')
        try:
            pct = float(line_rate) * 100
        except ValueError:
            pct = 0.0

        try:
            cplx = float(complexity)
        except ValueError:
            cplx = 0.0

        # Extract missing lines
        missing_lines = []
        lines_el = cls.find('lines')
        if lines_el is not None:
            for line in lines_el.findall('line'):
                if line.get('hits') == '0':
                    missing_lines.append(line.get('number'))
        
        missing_str = ", ".join(missing_lines) if missing_lines else "None"
        if len(missing_str) > 50:
            missing_str = missing_str[:47] + "..."
            
        status_icon = "🟢" if pct >= 90 else "🔴"
        md_lines.append(f"| `{filename}` | {pct:.2f}% {status_icon} | {cplx:.2f} | {missing_str} |")

    md_lines.append(f"")
    md_lines.append(f"> Generated by CI Pipeline")

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(md_lines))
    print(f"Generated markdown summary: {output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Transform Cobertura XML and check coverage.")
    parser.add_argument("xml_file", help="Path to Cobertura XML file")
    parser.add_argument("--fail-under", type=float, help="Minimum coverage percentage to pass")
    parser.add_argument(
        "--fail-under-per-file",
        type=float,
        help="Minimum per-file coverage percentage to pass",
    )
    parser.add_argument(
        "--max-complexity-overall",
        type=float,
        help="Maximum allowed overall complexity to pass",
    )
    parser.add_argument(
        "--max-complexity-per-file",
        type=float,
        help="Maximum allowed per-file complexity to pass",
    )
    parser.add_argument(
        "--require-real-complexity",
        action="store_true",
        help="Fail if lizard-based complexity cannot be computed",
    )
    
    args = parser.parse_args()
    
    transform_coverage(
        args.xml_file,
        args.fail_under,
        args.fail_under_per_file,
        args.max_complexity_overall,
        args.max_complexity_per_file,
        args.require_real_complexity,
    )
