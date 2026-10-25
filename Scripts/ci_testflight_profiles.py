#!/usr/bin/env python3
"""Create App Store profiles for the iPhone app and the Watch app.

Codemagic's ios_signing distribution_type/bundle_identifier prefetch only
downloads profiles that are already stored in Code signing identities. It
stops the build with "No matching profiles found" when that store is empty,
which is the case on the first TestFlight build. This script runs after
ios_signing has installed the pulse_distribution certificate into the
keychain. The PULSE ASC integration supplies the App Store Connect API
credentials. No CERTIFICATE_PRIVATE_KEY is required: the certificate already
exists, and creating a profile only needs its Apple resource id.
"""

from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Optional


PROFILE_TYPE = "IOS_APP_STORE"
DISTRIBUTION_TYPES = {"DISTRIBUTION", "IOS_DISTRIBUTION"}
PROFILES_DIR = Path.home() / "Library" / "MobileDevice" / "Provisioning Profiles"


def json_payload(text: str):
    decoder = json.JSONDecoder()
    for index, char in enumerate(text):
        if char not in "[{":
            continue
        try:
            value, _ = decoder.raw_decode(text[index:])
        except json.JSONDecodeError:
            continue
        if isinstance(value, (dict, list)):
            return value
    raise ValueError("App Store Connect command did not return JSON")


def resources(payload) -> list[dict]:
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict) and "id" in item]
    if isinstance(payload, dict):
        if "id" in payload and "attributes" in payload:
            return [payload]
        data = payload.get("data")
        if isinstance(data, list):
            return [item for item in data if isinstance(item, dict) and "id" in item]
        if isinstance(data, dict) and "id" in data:
            return [data]
    raise ValueError("Unrecognized App Store Connect payload")


def normalize_serial(value: str) -> str:
    cleaned = value.strip().lower().replace(":", "")
    if cleaned.startswith("serial="):
        cleaned = cleaned[len("serial=") :]
    stripped = cleaned.lstrip("0")
    return stripped or "0"


def pem_to_ders(text: str) -> list[bytes]:
    ders: list[bytes] = []
    begin = "-----BEGIN CERTIFICATE-----"
    end = "-----END CERTIFICATE-----"
    rest = text
    while True:
        start = rest.find(begin)
        if start < 0:
            break
        stop = rest.find(end, start)
        if stop < 0:
            break
        body = "".join(rest[start + len(begin) : stop].split())
        ders.append(base64.b64decode(body))
        rest = rest[stop + len(end) :]
    return ders


def certificate_ders(content: str) -> set[bytes]:
    stripped = content.strip()
    if "BEGIN CERTIFICATE" in stripped:
        return set(pem_to_ders(stripped))
    try:
        decoded = base64.b64decode(stripped, validate=True)
    except (ValueError, TypeError):
        decoded = b""
    if decoded.startswith(b"-----BEGIN"):
        return set(pem_to_ders(decoded.decode()))
    if decoded:
        return {decoded}
    return set()


def attribute(resource: dict, name: str):
    attributes = resource.get("attributes")
    if isinstance(attributes, dict):
        return attributes.get(name)
    return None


def relationship_ids(resource: dict, name: str) -> set[str]:
    relationships = resource.get("relationships")
    if not isinstance(relationships, dict):
        return set()
    relation = relationships.get(name)
    if not isinstance(relation, dict):
        return set()
    data = relation.get("data")
    if isinstance(data, dict):
        data = [data]
    if not isinstance(data, list):
        return set()
    return {item["id"] for item in data if isinstance(item, dict) and item.get("id")}


def select_distribution_certificate(
    api_certs: list[dict],
    local_ders: set[bytes],
    local_serials: set[str],
) -> dict:
    """Return the Apple Distribution certificate installed on this machine."""
    matches: list[dict] = []
    for cert in api_certs:
        content = attribute(cert, "certificateContent")
        ders = certificate_ders(content) if isinstance(content, str) else set()
        serial = attribute(cert, "serialNumber")
        serial_ok = isinstance(serial, str) and normalize_serial(serial) in local_serials
        if ders & local_ders or serial_ok:
            matches.append(cert)
    distribution = [
        cert
        for cert in matches
        if attribute(cert, "certificateType") in DISTRIBUTION_TYPES
    ]
    chosen = distribution or []
    if not chosen:
        if matches:
            kinds = sorted(
                {str(attribute(cert, "certificateType")) for cert in matches}
            )
            raise SystemExit(
                "The certificate in the build keychain is "
                f"{', '.join(kinds)}, not an Apple Distribution certificate. "
                "Codemagic reference pulse_distribution must be the Apple "
                "Distribution certificate."
            )
        raise SystemExit(
            "No Apple Distribution certificate in the developer account matches "
            "the certificate Codemagic installed from reference pulse_distribution. "
            "Check that the reference name in Code signing identities is exactly "
            "pulse_distribution."
        )
    chosen.sort(
        key=lambda cert: str(attribute(cert, "expirationDate") or ""),
        reverse=True,
    )
    return chosen[0]


def matching_profile(
    profiles: list[dict],
    bundle_resource_id: str,
    certificate_id: str,
) -> Optional[dict]:
    found: list[dict] = []
    for profile in profiles:
        if attribute(profile, "profileType") != PROFILE_TYPE:
            continue
        if attribute(profile, "profileState") != "ACTIVE":
            continue
        if bundle_resource_id not in relationship_ids(profile, "bundleId"):
            continue
        if certificate_id not in relationship_ids(profile, "certificates"):
            continue
        found.append(profile)
    if not found:
        return None
    found.sort(
        key=lambda profile: str(attribute(profile, "expirationDate") or ""),
        reverse=True,
    )
    return found[0]


def profile_bytes(profile: dict) -> bytes:
    content = attribute(profile, "profileContent")
    if not isinstance(content, str) or not content.strip():
        raise ValueError(f"Profile {profile.get('id')} has no profileContent")
    return base64.b64decode(content)


def write_profile(profile: dict, directory: Path) -> Path:
    uuid = attribute(profile, "uuid")
    if not isinstance(uuid, str) or not uuid:
        raise ValueError(f"Profile {profile.get('id')} has no uuid")
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{uuid}.mobileprovision"
    path.write_bytes(profile_bytes(profile))
    return path


def run_asc(args: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    command = ["app-store-connect", *args, "--no-color"]
    print("+ " + " ".join(command), flush=True)
    result = subprocess.run(command, text=True, capture_output=True)
    if check and result.returncode != 0:
        if result.stdout:
            print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        raise SystemExit(result.returncode)
    return result


def load_resources(args: list[str]) -> list[dict]:
    result = run_asc([*args, "--json"])
    return resources(json_payload(result.stdout))


def bundle_resource_id(identifier: str) -> str:
    found = load_resources(
        [
            "bundle-ids",
            "list",
            "--bundle-id-identifier",
            identifier,
            "--strict-match-identifier",
        ]
    )
    matches = [
        item
        for item in found
        if attribute(item, "identifier") == identifier and item.get("id")
    ]
    if len(matches) != 1:
        raise SystemExit(
            f"Expected one registered bundle id {identifier}, found {len(matches)}. "
            "Register it in Apple Developer → Identifiers with HealthKit on."
        )
    print(f"Bundle ID {identifier} resource {matches[0]['id']}")
    return str(matches[0]["id"])


def serial_of_der(der: bytes) -> str:
    result = subprocess.run(
        ["openssl", "x509", "-inform", "DER", "-noout", "-serial"],
        input=der,
        capture_output=True,
    )
    if result.returncode != 0:
        return ""
    return normalize_serial(result.stdout.decode())


def local_certificate_ders() -> set[bytes]:
    ders: set[bytes] = set()
    searches = [["security", "find-certificate", "-a", "-p"]]
    chains = subprocess.run(
        ["security", "list-keychains", "-d", "user"],
        text=True,
        capture_output=True,
    )
    if chains.returncode == 0:
        for line in chains.stdout.splitlines():
            keychain = line.strip().strip('"')
            if keychain:
                searches.append(["security", "find-certificate", "-a", "-p", keychain])
    for command in searches:
        listed = subprocess.run(command, text=True, capture_output=True)
        if listed.returncode == 0:
            ders.update(pem_to_ders(listed.stdout))
    certificate_path = os.environ.get("PULSE_DISTRIBUTION_CERTIFICATE", "")
    if certificate_path and os.path.isfile(certificate_path):
        raw = Path(certificate_path).read_bytes()
        if b"BEGIN CERTIFICATE" in raw:
            ders.update(pem_to_ders(raw.decode()))
        else:
            extracted = subprocess.run(
                [
                    "openssl",
                    "pkcs12",
                    "-in",
                    certificate_path,
                    "-nokeys",
                    "-passin",
                    "pass:",
                ],
                capture_output=True,
            )
            if extracted.returncode == 0:
                ders.update(pem_to_ders(extracted.stdout.decode(errors="replace")))
    if not ders:
        raise SystemExit(
            "The pulse_distribution certificate is not in the build keychain. "
            "Codemagic → Code signing identities → iOS certificates must contain "
            "an Apple Distribution certificate whose reference name is "
            "pulse_distribution."
        )
    return ders


def ensure_profile(
    identifier: str,
    bundle_id: str,
    certificate_id: str,
    profiles: list[dict],
) -> dict:
    existing = matching_profile(profiles, bundle_id, certificate_id)
    if existing is not None:
        print(
            f"Reusing App Store profile {existing['id']} "
            f"({attribute(existing, 'name')}) for {identifier}"
        )
        if not attribute(existing, "profileContent"):
            existing = load_resources(["profiles", "get", str(existing["id"])])[0]
        return existing

    kind = "Watch" if identifier.endswith(".watchkitapp") else "iOS"
    name = f"PULSE {kind} App Store"
    print(f"Creating App Store profile {name}")
    created = run_asc(
        [
            "profiles",
            "create",
            bundle_id,
            "--certificate-ids",
            certificate_id,
            "--type",
            PROFILE_TYPE,
            "--name",
            name,
            "--json",
        ],
        check=False,
    )
    if created.returncode != 0:
        combined = f"{created.stdout}\n{created.stderr}"
        if "409" not in combined and "ENTITY_ERROR" not in combined:
            if created.stdout:
                print(created.stdout)
            if created.stderr:
                print(created.stderr, file=sys.stderr)
            raise SystemExit(created.returncode)
        print(f"Profile name already exists. Replacing {name}.")
        named = [
            profile
            for profile in load_resources(
                ["profiles", "list", "--type", PROFILE_TYPE, "--name", name]
            )
            if attribute(profile, "name") == name
        ]
        for profile in named:
            run_asc(["profiles", "delete", str(profile["id"]), "--ignore-not-found"])
        created = run_asc(
            [
                "profiles",
                "create",
                bundle_id,
                "--certificate-ids",
                certificate_id,
                "--type",
                PROFILE_TYPE,
                "--name",
                name,
                "--json",
            ]
        )
    made = resources(json_payload(created.stdout))
    if len(made) != 1:
        raise SystemExit(f"Expected one created profile for {identifier}.")
    print(f"Created App Store profile {made[0]['id']} for {identifier}")
    return made[0]


def profiles_contain_bundle(path: Path, identifier: str) -> None:
    decoded = subprocess.run(
        ["security", "cms", "-D", "-i", str(path)],
        capture_output=True,
    )
    if decoded.returncode != 0:
        print(f"Could not decode {path.name}; leaving the profile in place.")
        return
    text = decoded.stdout.decode(errors="replace")
    if identifier not in text:
        raise SystemExit(f"{path} does not contain bundle id {identifier}.")
    print(f"{path.name} is an App Store profile for {identifier}")


def main() -> None:
    phone = os.environ.get("BUNDLE_ID", "")
    watch = os.environ.get("WATCH_BUNDLE_ID", "")
    if not phone or not watch:
        raise SystemExit("BUNDLE_ID and WATCH_BUNDLE_ID are required.")

    local_ders = local_certificate_ders()
    local_serials = {serial_of_der(der) for der in local_ders}
    local_serials.discard("")
    certificates = load_resources(
        ["certificates", "list", "--profile-type", PROFILE_TYPE]
    )
    certificate = select_distribution_certificate(
        certificates, local_ders, local_serials
    )
    certificate_id = str(certificate["id"])
    print(
        "Using Apple Distribution certificate "
        f"{certificate_id} "
        f"({attribute(certificate, 'displayName') or attribute(certificate, 'name')}), "
        f"serial {attribute(certificate, 'serialNumber')}, "
        f"expires {attribute(certificate, 'expirationDate')}"
    )

    profiles = load_resources(["profiles", "list", "--type", PROFILE_TYPE])
    for identifier in (phone, watch):
        bundle_id = bundle_resource_id(identifier)
        profile = ensure_profile(identifier, bundle_id, certificate_id, profiles)
        path = write_profile(profile, PROFILES_DIR)
        profiles_contain_bundle(path, identifier)

    print(f"App Store profiles saved in {PROFILES_DIR}")


def _self_test() -> None:
    der = b"\x30\x03\x01\x01\xff"
    pem = (
        "-----BEGIN CERTIFICATE-----\n"
        + base64.encodebytes(der).decode()
        + "-----END CERTIFICATE-----\n"
    )
    assert pem_to_ders(pem) == [der]
    content = base64.b64encode(der).decode()
    payload = json_payload('log line\n[{"id": "C1", "attributes": {"a": 1}}]')
    assert resources(payload)[0]["id"] == "C1"
    certs = [
        {
            "id": "DEV",
            "attributes": {
                "certificateType": "DEVELOPMENT",
                "certificateContent": content,
                "serialNumber": "0A",
                "expirationDate": "2027-01-01T00:00:00+00:00",
            },
        },
        {
            "id": "DIST",
            "attributes": {
                "certificateType": "DISTRIBUTION",
                "certificateContent": content,
                "serialNumber": "0A",
                "expirationDate": "2027-10-25T00:00:00+00:00",
            },
        },
    ]
    chosen = select_distribution_certificate(certs, {der}, {"a"})
    assert chosen["id"] == "DIST"
    try:
        select_distribution_certificate(certs[:1], {der}, {"a"})
    except SystemExit as error:
        assert "not an Apple Distribution" in str(error)
    else:
        raise AssertionError("development certificate was accepted")
    try:
        select_distribution_certificate(certs, {b"\x00"}, set())
    except SystemExit as error:
        assert "pulse_distribution" in str(error)
    else:
        raise AssertionError("unmatched certificate was accepted")

    profile = {
        "id": "P1",
        "attributes": {
            "name": "PULSE App Store",
            "profileType": PROFILE_TYPE,
            "profileState": "ACTIVE",
            "uuid": "11111111-2222-3333-4444-555555555555",
            "profileContent": base64.b64encode(b"profile-bytes").decode(),
            "expirationDate": "2027-10-25T00:00:00+00:00",
        },
        "relationships": {
            "bundleId": {"data": {"id": "BID", "type": "bundleIds"}},
            "certificates": {"data": [{"id": "DIST", "type": "certificates"}]},
        },
    }
    stale = {
        "id": "P0",
        "attributes": {
            "profileType": PROFILE_TYPE,
            "profileState": "INVALID",
            "expirationDate": "2028-01-01T00:00:00+00:00",
        },
        "relationships": profile["relationships"],
    }
    assert matching_profile([stale, profile], "BID", "DIST")["id"] == "P1"
    assert matching_profile([profile], "OTHER", "DIST") is None
    assert profile_bytes(profile) == b"profile-bytes"
    print("self-test ok")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        _self_test()
    else:
        main()
