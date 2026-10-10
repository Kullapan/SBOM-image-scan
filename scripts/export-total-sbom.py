#!/usr/bin/env python3
"""
Script: export-total-sbom.py
Description: Aggregates detailed components and exports CycloneDX SBOM across all projects
             in OWASP Dependency-Track without external dependencies.
"""

import os
import sys
import json
import csv
import urllib.request
import urllib.error

def load_env(env_path):
    config = {}
    if os.path.exists(env_path):
        with open(env_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    config[k.strip()] = v.strip().strip('"').strip("'")
    return config

def api_get(url, api_key, accept="application/json"):
    req = urllib.request.Request(url, headers={
        "X-Api-Key": api_key,
        "Accept": accept
    })
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"HTTP Error {e.code} for {url}", file=sys.stderr)
        return None

def fetch_all_project_components(dtrack_url, p_uuid, api_key):
    all_comps = []
    page = 1
    page_size = 100
    while True:
        url = f"{dtrack_url}/api/v1/component/project/{p_uuid}?pageNumber={page}&pageSize={page_size}"
        data = api_get(url, api_key)
        if not data:
            break
        all_comps.extend(data)
        if len(data) < page_size:
            break
        page += 1
    return all_comps

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    env_path = os.path.join(script_dir, "..", "phase1-local-poc", ".env")
    env_vars = load_env(env_path)

    dtrack_url = os.environ.get("DTRACK_URL", env_vars.get("API_BASE_URL", "http://localhost:8081")).rstrip("/")
    api_key = os.environ.get("DTRACK_API_KEY", env_vars.get("DTRACK_API_KEY", ""))

    output_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(script_dir, "..", "reports")
    os.makedirs(output_dir, exist_ok=True)

    if not api_key:
        print("ERROR: DTRACK_API_KEY is not set.", file=sys.stderr)
        sys.exit(1)

    print("=================================================================")
    print("[+] EXPORTING TOTAL SBOM & DETAILED COMPONENT INVENTORY REPORT")
    print(f"  Dependency-Track: {dtrack_url}")
    print(f"  Output Directory: {output_dir}")
    print("=================================================================")

    projects = api_get(f"{dtrack_url}/api/v1/project", api_key) or []
    print(f"Found {len(projects)} projects in Dependency-Track portfolio.\n")

    print("-" * 75)
    print(f"{'PROJECT':<25} {'VERSION':<12} {'PARENT APP':<20} {'COMPONENTS':<12}")
    print("-" * 75)

    summary_csv_path = os.path.join(output_dir, "portfolio-inventory-summary.csv")
    detail_csv_path = os.path.join(output_dir, "total-components-detail.csv")
    unique_csv_path = os.path.join(output_dir, "total-unique-components.csv")

    all_components_detail = []
    unique_components_map = {}
    total_components_count = 0

    with open(summary_csv_path, "w", newline="", encoding="utf-8") as sumfile:
        sum_writer = csv.writer(sumfile)
        sum_writer.writerow(["ProjectName", "ProjectVersion", "ParentApp", "ComponentCount", "Vulnerabilities"])

        for p in projects:
            p_uuid = p.get("uuid")
            name = p.get("name")
            version = p.get("version", "none")

            details = api_get(f"{dtrack_url}/api/v1/project/{p_uuid}", api_key) or {}
            parent_name = details.get("parent", {}).get("name", "None (Root)")
            metrics = details.get("metrics") or {}
            comp_count = metrics.get("components", 0)
            vuln_count = metrics.get("vulnerabilities", 0)

            total_components_count += comp_count
            print(f"{name:<25} {version:<12} {parent_name:<20} {comp_count:<12}")
            sum_writer.writerow([name, version, parent_name, comp_count, vuln_count])

            if comp_count > 0:
                # 1. Fetch detailed components for this project (across all pages)
                components_list = fetch_all_project_components(dtrack_url, p_uuid, api_key)

                for c in components_list:
                    c_group = c.get("group") or ""
                    c_name = c.get("name") or ""
                    c_version = c.get("version") or ""
                    c_purl = c.get("purl") or ""
                    c_classifier = c.get("classifier") or "LIBRARY"
                    c_license = c.get("resolvedLicense", {}).get("licenseId") or c.get("license") or "Unspecified"

                    all_components_detail.append([
                        parent_name,
                        name,
                        version,
                        c_group,
                        c_name,
                        c_version,
                        c_purl,
                        c_license,
                        c_classifier
                    ])

                    # Track unique component across the entire portfolio
                    purl_key = c_purl if c_purl else f"{c_group}:{c_name}@{c_version}"
                    proj_label = f"{name} ({version})"
                    if purl_key not in unique_components_map:
                        unique_components_map[purl_key] = {
                            "group": c_group,
                            "name": c_name,
                            "version": c_version,
                            "purl": c_purl,
                            "license": c_license,
                            "classifier": c_classifier,
                            "projects": set([proj_label])
                        }
                    else:
                        unique_components_map[purl_key]["projects"].add(proj_label)

                # 2. Export individual CycloneDX JSON SBOM
                safe_name = f"{name}-{version}".replace("/", "_").replace(":", "_")
                bom_url = f"{dtrack_url}/api/v1/bom/cyclonedx/project/{p_uuid}?format=json"
                bom_data = api_get(bom_url, api_key, accept="application/vnd.cyclonedx+json, application/json")
                if bom_data:
                    bom_file = os.path.join(output_dir, f"{safe_name}-cyclonedx.json")
                    with open(bom_file, "w", encoding="utf-8") as bf:
                        json.dump(bom_data, bf, indent=2)

    # Write Detailed Components CSV
    with open(detail_csv_path, "w", newline="", encoding="utf-8") as detfile:
        det_writer = csv.writer(detfile)
        det_writer.writerow([
            "ParentApp",
            "ProjectName",
            "ProjectVersion",
            "Group",
            "ComponentName",
            "ComponentVersion",
            "PURL",
            "License",
            "Classifier"
        ])
        det_writer.writerows(all_components_detail)

    # Write Unique Components Across Portfolio CSV
    with open(unique_csv_path, "w", newline="", encoding="utf-8") as ufile:
        u_writer = csv.writer(ufile)
        u_writer.writerow([
            "Group",
            "ComponentName",
            "ComponentVersion",
            "PURL",
            "License",
            "Classifier",
            "ProjectsUsageCount",
            "UsedInProjects"
        ])
        for key, item in sorted(unique_components_map.items()):
            u_writer.writerow([
                item["group"],
                item["name"],
                item["version"],
                item["purl"],
                item["license"],
                item["classifier"],
                len(item["projects"]),
                "; ".join(sorted(item["projects"]))
            ])

    print("-" * 75)
    print(f"[OK] Total Project-Component Instances: {len(all_components_detail)}")
    print(f"[OK] Total Unique Components in Enterprise: {len(unique_components_map)}")
    print(f"[OK] Summary Report:           {summary_csv_path}")
    print(f"[OK] Detail Components CSV:    {detail_csv_path}")
    print(f"[OK] Unique Components CSV:    {unique_csv_path}")
    print(f"[OK] Individual CycloneDX BOM: {output_dir}/*.json")
    print("=================================================================")

if __name__ == "__main__":
    main()
