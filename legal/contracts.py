"""
Fictional contract clauses for the demo.

Every firm gets its own deterministic set of contracts, generated from the
firm's slug, so a firm added in Terraform tomorrow gets realistic data with
no extra work. Nothing here is real: firms, counterparties and terms are all
invented.

Each row is one clause of one contract. Clauses are the unit people search
for ("what's our cap on liability with Northwind?"), so they're the unit we
store in turbopuffer.
"""

from __future__ import annotations

import hashlib
import random

CONTRACT_TYPES = ["NDA", "MSA", "SaaS Agreement", "Commercial Lease", "Employment Agreement", "Supplier Agreement"]
GOVERNING_LAW = ["New York", "Delaware", "California", "Texas", "England and Wales", "Ontario"]
COUNTERPARTIES = [
    "Northwind Logistics", "Bluefin Analytics", "Cedar & Pike Retail", "Orbital Health Systems",
    "Kestrel Robotics", "Harborview Properties", "Larkspur Media", "Summit Ridge Energy",
    "Quillon Software", "Ironbark Construction", "Meridian Foods", "Copperline Telecom",
    "Fathom Biotech", "Granite Peak Capital", "Tidewater Shipping", "Verdant Farms Co-op",
]
MATTERS = ["Vendor onboarding", "Office expansion", "Product launch", "Acquisition diligence",
           "Executive hiring", "Data platform migration", "Supply chain renegotiation"]

# Clause templates. {cp} is the counterparty, the others are filled per contract.
CLAUSES = {
    "Limitation of Liability": [
        "Except for breaches of confidentiality or indemnification obligations, neither party's aggregate "
        "liability to {cp} under this Agreement shall exceed {cap_multiple} times the fees paid in the "
        "{cap_months} months preceding the claim. Neither party is liable for lost profits, lost revenue, "
        "or indirect, incidental, special or consequential damages.",
        "{cp}'s total liability for all claims arising out of this Agreement is capped at ${cap_usd:,}. The cap "
        "does not apply to gross negligence, wilful misconduct, or a party's payment obligations.",
    ],
    "Indemnification": [
        "{cp} shall defend, indemnify and hold harmless the Client from third-party claims alleging that the "
        "Services infringe any patent, copyright or trademark, provided the Client gives prompt written notice "
        "within {notice_days} days and reasonable cooperation.",
        "Each party will indemnify the other against losses arising from its breach of applicable data "
        "protection law. Indemnified losses include regulatory fines to the extent permitted by law.",
    ],
    "Termination": [
        "Either party may terminate this Agreement for convenience on {term_notice} days' written notice. Either "
        "party may terminate immediately if the other materially breaches and fails to cure within "
        "{cure_days} days of notice.",
        "The Client may terminate for convenience after the initial term of {term_years} years. On termination "
        "{cp} shall return or destroy all Client data within {return_days} days and certify in writing.",
    ],
    "Confidentiality": [
        "Each party shall protect the other's Confidential Information with at least reasonable care and use it "
        "only to perform this Agreement. These obligations survive for {conf_years} years after termination, "
        "and indefinitely for trade secrets.",
        "Confidential Information excludes information that is public through no fault of the recipient, "
        "independently developed, or lawfully received from a third party without restriction.",
    ],
    "Payment Terms": [
        "Fees are invoiced {billing} in advance and payable within {net_days} days of invoice. Late amounts "
        "accrue interest at {late_pct}% per month. {cp} may suspend Services for invoices more than "
        "{suspend_days} days overdue.",
        "Pricing is fixed for the initial term. Thereafter {cp} may increase fees by no more than "
        "{uplift_pct}% per renewal year with {uplift_notice} days' notice.",
    ],
    "Auto-Renewal": [
        "This Agreement renews automatically for successive {renew_months}-month periods unless either party "
        "gives notice of non-renewal at least {nonrenew_days} days before the end of the current term.",
    ],
    "Data Protection": [
        "{cp} shall process personal data only on documented instructions, maintain SOC 2 Type II "
        "certification, and notify the Client of any personal data breach within {breach_hours} hours of "
        "becoming aware of it.",
        "Personal data shall be stored only in {data_region}. Sub-processors require {subproc_days} days' "
        "prior notice, and the Client may object on reasonable grounds.",
    ],
    "Non-Compete": [
        "For {noncompete_months} months after employment ends, the Employee shall not work for a direct "
        "competitor within {noncompete_miles} miles of any office where the Employee worked in the final year.",
        "The Employee shall not solicit Company clients or employees for {nonsolicit_months} months after "
        "employment ends.",
    ],
    "Rent and Escalation": [
        "Base rent is ${rent_usd:,} per month, increasing by {escalation_pct}% on each anniversary of the "
        "commencement date. The Tenant pays its pro rata share of operating expenses and property taxes.",
    ],
    "Assignment": [
        "Neither party may assign this Agreement without the other's prior written consent, except to a "
        "successor in a merger or sale of substantially all assets, with notice within {assign_days} days.",
    ],
    "Force Majeure": [
        "Neither party is liable for delay caused by events beyond its reasonable control, including pandemic, "
        "cyberattack on third-party infrastructure, or acts of government. If the event lasts more than "
        "{fm_days} days, either party may terminate.",
    ],
    "Service Levels": [
        "{cp} guarantees {uptime}% monthly uptime. For each 0.1% below target the Client receives a "
        "{credit_pct}% service credit, capped at {credit_cap}% of monthly fees. Credits are the sole remedy "
        "for availability failures.",
    ],
}

# Which clauses appear in which kind of contract.
CLAUSES_FOR_TYPE = {
    "NDA": ["Confidentiality", "Termination", "Assignment"],
    "MSA": ["Limitation of Liability", "Indemnification", "Termination", "Payment Terms", "Confidentiality",
            "Force Majeure"],
    "SaaS Agreement": ["Service Levels", "Data Protection", "Limitation of Liability", "Auto-Renewal",
                       "Payment Terms", "Termination"],
    "Commercial Lease": ["Rent and Escalation", "Termination", "Assignment", "Force Majeure"],
    "Employment Agreement": ["Non-Compete", "Confidentiality", "Termination"],
    "Supplier Agreement": ["Payment Terms", "Indemnification", "Limitation of Liability", "Force Majeure",
                           "Auto-Renewal"],
}


def _rng(seed: str) -> random.Random:
    return random.Random(int(hashlib.sha256(seed.encode()).hexdigest()[:12], 16))


def _values(r: random.Random) -> dict:
    return {
        "cap_multiple": r.choice([1, 2, 3]), "cap_months": r.choice([6, 12, 24]),
        "cap_usd": r.choice([250_000, 500_000, 1_000_000, 2_500_000, 5_000_000]),
        "notice_days": r.choice([10, 15, 30]), "term_notice": r.choice([30, 60, 90]),
        "cure_days": r.choice([15, 30, 45]), "term_years": r.choice([1, 2, 3, 5]),
        "return_days": r.choice([15, 30, 60]), "conf_years": r.choice([2, 3, 5, 7]),
        "billing": r.choice(["monthly", "quarterly", "annually"]), "net_days": r.choice([15, 30, 45, 60]),
        "late_pct": r.choice([1, 1.5]), "suspend_days": r.choice([30, 45, 60]),
        "uplift_pct": r.choice([3, 5, 7]), "uplift_notice": r.choice([30, 60, 90]),
        "renew_months": r.choice([12, 24]), "nonrenew_days": r.choice([30, 60, 90]),
        "breach_hours": r.choice([24, 48, 72]),
        "data_region": r.choice(["the United States", "the European Economic Area", "Canada"]),
        "subproc_days": r.choice([15, 30]), "noncompete_months": r.choice([6, 12, 18]),
        "noncompete_miles": r.choice([25, 50, 100]), "nonsolicit_months": r.choice([12, 24]),
        "rent_usd": r.choice([18_500, 42_000, 76_250, 128_000]), "escalation_pct": r.choice([2, 2.5, 3, 4]),
        "assign_days": r.choice([15, 30]), "fm_days": r.choice([30, 60, 90]),
        "uptime": r.choice([99.5, 99.9, 99.95]), "credit_pct": r.choice([5, 10]),
        "credit_cap": r.choice([25, 50]),
    }


def generate(firm_slug: str, n_contracts: int = 14) -> list[dict]:
    """All clause rows for one firm. Same slug in, same rows out."""
    r = _rng(firm_slug)
    rows = []
    for c in range(n_contracts):
        ctype = CONTRACT_TYPES[c % len(CONTRACT_TYPES)] if c < len(CONTRACT_TYPES) else r.choice(CONTRACT_TYPES)
        cp = r.choice(COUNTERPARTIES)
        year = r.choice([2021, 2022, 2023, 2024, 2025, 2026])
        law = r.choice(GOVERNING_LAW)
        matter = r.choice(MATTERS)
        value = r.choice([45_000, 120_000, 360_000, 850_000, 1_400_000, 3_200_000])
        title = f"{ctype} with {cp} ({year})"
        vals = _values(r)
        for clause in CLAUSES_FOR_TYPE[ctype]:
            text = r.choice(CLAUSES[clause]).format(cp=cp, **vals)
            rows.append({
                "id": f"{firm_slug}-c{c:02d}-{clause.lower().replace(' ', '-')}",
                "content": f"{clause}. {text}",
                "clause": clause,
                "title": title,
                "contract_type": ctype,
                "counterparty": cp,
                "governing_law": law,
                "signed_year": year,
                "matter": matter,
                "value_usd": value,
            })
    return rows


EXAMPLE_QUESTIONS = [
    "What is our liability cap and what's excluded from it?",
    "How quickly must a vendor tell us about a data breach?",
    "Which contracts renew automatically and how much notice do we need to cancel?",
    "non-compete radius",
    "Can the supplier raise prices at renewal?",
    "What happens to our data when the agreement ends?",
]
