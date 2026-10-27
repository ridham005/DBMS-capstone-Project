#!/bin/bash
# Rebuild the UPIShield database (Linux / macOS). Run from the project root.
cd "$(dirname "$0")"
mysql --local-infile=1 -u root -p < sql/00_rebuild.sql
