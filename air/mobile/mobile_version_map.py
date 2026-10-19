"""Validate a text-catalog-only update against the pinned mobile review map."""
import hashlib
import xml.etree.ElementTree as ET


def validate_text_catalog_update(baseline, current, baseline_sha):
    if hashlib.sha256(baseline).hexdigest() != baseline_sha:
        raise ValueError('Baseline version map does not match the pinned content')
    if any(b'<!DOCTYPE' in data.upper() or b'<!ENTITY' in data.upper() for data in (baseline, current)):
        raise ValueError('Unexpected XML declaration')
    old, new = ET.fromstring(baseline), ET.fromstring(current)
    counters = []
    for root in (old, new):
        fields = root.findall('text')
        if root.tag != 'data' or len(fields) != 1 or len(fields[0]) or fields[0].attrib:
            raise ValueError('Unexpected text catalog schema')
        value = (fields[0].text or '').strip()
        if not value.isascii() or not value.isdecimal():
            raise ValueError('Invalid text catalog counter')
        counters.append(int(value))
        fields[0].text = '0'
        for node in root.iter():
            node.text = (node.text or '').strip()
            node.tail = (node.tail or '').strip()
    if counters[1] < counters[0] or ET.tostring(old) != ET.tostring(new):
        raise ValueError('Executable/resource versions changed; review and rebuild the content pack')
    return counters
