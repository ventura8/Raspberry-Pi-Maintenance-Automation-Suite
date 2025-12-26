import xml.etree.ElementTree as ET
import sys
import os

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
    # 6px approx per char + padding
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


    # Ensure assets directory exists
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    
    with open(output_path, "w") as f:
        f.write(svg)
    print(f"Generated badge: {output_path} ({coverage_str})")

def transform_coverage(xml_file):
    if not os.path.exists(xml_file):
        print(f"Error: {xml_file} not found")
        sys.exit(1)

    try:
        tree = ET.parse(xml_file)
        root = tree.getroot()
        
        # Generate badge from root line-rate
        root_line_rate = root.get("line-rate", "0")
        generate_badge(root_line_rate)

    except ET.ParseError as e:
        print(f"Error parsing XML: {e}")
        sys.exit(1)

    packages_el = root.find('packages')
    if packages_el is None:
        # If no packages, possibly create one or just exit (original behavior was exit if None)
        # But maybe we should continue to at least have the badge?
        # The remote script creates it if None. sticking to local logic for now which was printing error
        # but since I added badge generation before this check, badge is safe.
        print("No <packages> element found")
        sys.exit(1)

    # Collect all classes from all existing packages
    all_classes = []
    for pkg in packages_el.findall('package'):
        classes_el = pkg.find('classes')
        if classes_el is not None:
            all_classes.extend(classes_el.findall('class'))

    # Clear existing packages
    packages_el.clear()

    # Create new package per class
    for cls in all_classes:
        filename = cls.get('filename')
        # Use basename or relative path as package name
        pkg_name = filename 
        
        new_pkg = ET.SubElement(packages_el, 'package')
        new_pkg.set('name', pkg_name)
        
        # Copy rate attributes from class to package
        for attr in ['line-rate', 'branch-rate', 'complexity']:
            if val := cls.get(attr):
                new_pkg.set(attr, val)
            else:
                new_pkg.set(attr, '0.0')

        # Create classes container
        new_classes = ET.SubElement(new_pkg, 'classes')
        new_classes.append(cls)

    tree.write(xml_file, encoding='UTF-8', xml_declaration=True)
    print(f"Successfully transformed {xml_file}: Split {len(all_classes)} classes into separate packages.")
    
    # Generate Markdown Summary
    generate_markdown_summary(all_classes, root_line_rate)

def generate_markdown_summary(classes, overall_rate, output_path="code-coverage-results.md"):
    try:
        overall_pct = float(overall_rate) * 100
    except ValueError:
        overall_pct = 0.0

    md_lines = []
    md_lines.append(f"## Code Coverage Summary")
    md_lines.append(f"")
    md_lines.append(f"**Overall Coverage:** {overall_pct:.2f}%")
    md_lines.append(f"")
    md_lines.append(f"| File | Coverage | Lines |")
    md_lines.append(f"| :--- | :---: | :---: |")

    for cls in classes:
        filename = cls.get('filename')
        line_rate = cls.get('line-rate', '0')
        try:
            pct = float(line_rate) * 100
        except ValueError:
            pct = 0.0
            
        # Optional: Get lines valid vs covered if available? 
        # kcov XML usually has line-rate. 
        # Note: kcov XML 'lines' element inside class has total lines.
        # But we are iterating 'class' elements which have children 'lines' -> 'line'.
        # We can count them or rely on attributes? 
        # Attributes often have complexity but maybe not raw counts unless we calculate.
        # Let's simple use percentage.
        
        status_icon = "🟢" if pct >= 90 else "🔴"
        md_lines.append(f"| `{filename}` | {pct:.2f}% {status_icon} | - |")

    md_lines.append(f"")
    md_lines.append(f"> Generated by CI Pipeline")

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(md_lines))
    print(f"Generated markdown summary: {output_path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python transform_coverage.py <cobertura.xml>")
        sys.exit(1)
    
    transform_coverage(sys.argv[1])
