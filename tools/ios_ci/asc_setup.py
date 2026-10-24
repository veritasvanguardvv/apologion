#!/usr/bin/env python3
"""One-time App Store Connect setup for the TestFlight workflow (runs on any OS, no Mac needed).

Needs an App Store Connect *Team* API key with the Admin role (Users and Access >
Integrations > App Store Connect API). Install deps: pip install pyjwt cryptography requests

  check    Verify the key; show bundle id, app record, distribution certs, profiles.
  signing  Register the bundle id if needed, create an Apple Distribution certificate
           (+ private key, packed as .p12) and an App Store provisioning profile, and
           write them to --out. With --set-secrets, also store the six repo secrets via `gh`.
  testers  Create an internal TestFlight group that gets every build, and add --email.

Nothing here deletes or revokes anything in the Apple account.
"""
import argparse, base64, datetime as dt, json, os, secrets, subprocess, sys, time

import jwt, requests
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com"


class ASC:
    def __init__(self, key_id, issuer_id, p8_path):
        self.key_id, self.issuer_id = key_id, issuer_id
        self.p8 = open(p8_path).read()
        self._tok, self._exp = None, 0

    def token(self):
        now = int(time.time())
        if not self._tok or now > self._exp - 60:
            self._exp = now + 15 * 60
            self._tok = jwt.encode({"iss": self.issuer_id, "iat": now, "exp": self._exp,
                                    "aud": "appstoreconnect-v1"}, self.p8, algorithm="ES256",
                                   headers={"kid": self.key_id, "typ": "JWT"})
        return self._tok

    def req(self, method, path, body=None, params=None, ok=(200, 201, 204)):
        r = requests.request(method, API + path, params=params, json=body, timeout=60,
                             headers={"Authorization": "Bearer " + self.token()})
        if r.status_code not in ok:
            raise SystemExit(f"{method} {path} -> HTTP {r.status_code}\n{r.text[:2000]}")
        return r.json() if r.text else {}

    def get_all(self, path, params=None):
        out, url, params = [], path, dict(params or {}, limit=200)
        while url:
            d = self.req("GET", url, params=params)
            out += d.get("data", [])
            nxt = d.get("links", {}).get("next")
            url, params = (nxt.replace(API, ""), None) if nxt else (None, None)
        return out


def find_bundle(asc, ident):
    for b in asc.get_all("/v1/bundleIds", {"filter[identifier]": ident}):
        if b["attributes"]["identifier"] == ident:
            return b
    return None


def find_app(asc, ident):
    apps = asc.get_all("/v1/apps", {"filter[bundleId]": ident})
    return next((a for a in apps if a["attributes"]["bundleId"] == ident), None)


def dist_certs(asc):
    return asc.get_all("/v1/certificates", {"filter[certificateType]": "DISTRIBUTION,IOS_DISTRIBUTION"})


def team_of(cert_der):
    c = x509.load_der_x509_certificate(cert_der)
    ou = c.subject.get_attributes_for_oid(NameOID.ORGANIZATIONAL_UNIT_NAME)
    return ou[0].value if ou else None


def make_p12(key, cert_der, password, name):
    cert = x509.load_der_x509_certificate(cert_der)
    # SHA1/3DES PKCS#12 so macOS `security import` accepts it on every Xcode/macOS version.
    enc = (serialization.PrivateFormat.PKCS12.encryption_builder().kdf_rounds(50000)
           .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
           .hmac_hash(hashes.SHA1()).build(password.encode()))
    return pkcs12.serialize_key_and_certificates(name.encode(), key, cert, None, enc)


def cmd_check(asc, a):
    b = find_bundle(asc, a.bundle_id)
    print("Bundle id:", f"registered ({b['id']})" if b else "NOT registered yet (signing will register it)")
    app = find_app(asc, a.bundle_id)
    print("App record:", f"{app['attributes']['name']} (Apple ID {app['id']})" if app
          else "MISSING: create it at appstoreconnect.apple.com > Apps > + > New App")
    certs = dist_certs(asc)
    print(f"Distribution certificates: {len(certs)}")
    for c in certs:
        at = c["attributes"]
        print(f"  - {at.get('name')} [{at.get('certificateType')}] expires {at.get('expirationDate')}")
        if at.get("certificateContent"):
            print("    team:", team_of(base64.b64decode(at["certificateContent"])))
    profs = asc.get_all("/v1/profiles", {"filter[profileType]": "IOS_APP_STORE"})
    print(f"App Store profiles: {[p['attributes']['name'] for p in profs]}")


def cmd_signing(asc, a):
    out = os.path.expanduser(a.out)
    os.makedirs(out, mode=0o700, exist_ok=True)
    b = find_bundle(asc, a.bundle_id)
    if not b:
        b = asc.req("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
            "identifier": a.bundle_id, "name": a.app_name, "platform": "IOS"}}})["data"]
        print("Registered bundle id", a.bundle_id)

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (x509.CertificateSigningRequestBuilder()
           .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, f"{a.app_name} CI"),
                                    x509.NameAttribute(NameOID.COUNTRY_NAME, "US")]))
           .sign(key, hashes.SHA256()))
    csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode()
    cert = asc.req("POST", "/v1/certificates", {"data": {"type": "certificates", "attributes": {
        "certificateType": "DISTRIBUTION", "csrContent": csr_pem}}})["data"]
    der = base64.b64decode(cert["attributes"]["certificateContent"])
    team = team_of(der)
    print(f"Created Apple Distribution certificate {cert['id']} (team {team}), expires",
          cert["attributes"].get("expirationDate"))

    pw = secrets.token_urlsafe(24)
    p12 = make_p12(key, der, pw, f"{a.app_name} CI")
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M")
    prof = asc.req("POST", "/v1/profiles", {"data": {"type": "profiles",
        "attributes": {"name": f"{a.app_name} App Store CI {stamp}", "profileType": "IOS_APP_STORE"},
        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": b["id"]}},
                          "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]}}}})["data"]
    prof_bytes = base64.b64decode(prof["attributes"]["profileContent"])
    print("Created provisioning profile", prof["attributes"]["name"])

    files = {
        "dist_key.pem": key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                          serialization.NoEncryption()),
        "dist_cert.cer": der, "dist.p12": p12, "dist_p12_password.txt": pw.encode(),
        "AppStore.mobileprovision": prof_bytes,
        "info.json": json.dumps({"team_id": team, "certificate_id": cert["id"], "profile_id": prof["id"],
                                 "profile_name": prof["attributes"]["name"], "bundle_id": a.bundle_id},
                                indent=2).encode(),
    }
    for n, d in files.items():
        p = os.path.join(out, n)
        with open(p, "wb") as f:
            f.write(d)
        os.chmod(p, 0o600)
    print("Wrote signing files to", out)

    if a.set_secrets:
        vals = {
            "ASC_KEY_ID": asc.key_id, "ASC_ISSUER_ID": asc.issuer_id, "ASC_KEY_P8": asc.p8,
            "IOS_DIST_P12_BASE64": base64.b64encode(p12).decode(), "IOS_DIST_P12_PASSWORD": pw,
            "IOS_PROFILE_BASE64": base64.b64encode(prof_bytes).decode(),
        }
        for k, v in vals.items():
            subprocess.run(["gh", "secret", "set", k, "-R", a.repo], input=v.encode(), check=True)
            print("Set repo secret", k)


def cmd_testers(asc, a):
    app = find_app(asc, a.bundle_id)
    if not app:
        raise SystemExit("No app record for the bundle id yet; create it in App Store Connect first.")
    groups = asc.get_all(f"/v1/apps/{app['id']}/betaGroups")
    g = next((x for x in groups if x["attributes"].get("isInternalGroup")
              and x["attributes"]["name"] == a.group), None)
    if not g:
        g = asc.req("POST", "/v1/betaGroups", {"data": {"type": "betaGroups",
            "attributes": {"name": a.group, "isInternalGroup": True, "hasAccessToAllBuilds": True},
            "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}})["data"]
        print("Created internal group", a.group)
    if a.email:
        r = asc.req("POST", "/v1/betaTesters", {"data": {"type": "betaTesters",
            "attributes": {"email": a.email, "firstName": a.first or None, "lastName": a.last or None},
            "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": g["id"]}]}}}},
            ok=(200, 201, 409))
        print("Added tester", a.email, "" if r.get("data") else r)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--key-id", required=True)
    ap.add_argument("--issuer-id", required=True)
    ap.add_argument("--p8", required=True, help="path to AuthKey_XXXX.p8")
    ap.add_argument("--bundle-id", default="com.veritasvanguard.apologion")
    ap.add_argument("--app-name", default="Apologion")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("check")
    s = sub.add_parser("signing")
    s.add_argument("--out", default="~/.apologion-ios-signing")
    s.add_argument("--set-secrets", action="store_true")
    s.add_argument("--repo", default="veritasvanguardvv/apologion")
    t = sub.add_parser("testers")
    t.add_argument("--group", default="Apologion testers")
    t.add_argument("--email")
    t.add_argument("--first", default="")
    t.add_argument("--last", default="")
    a = ap.parse_args()
    asc = ASC(a.key_id, a.issuer_id, a.p8)
    {"check": cmd_check, "signing": cmd_signing, "testers": cmd_testers}[a.cmd](asc, a)


if __name__ == "__main__":
    main()
