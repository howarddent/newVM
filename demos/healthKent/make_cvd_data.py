#!/usr/bin/env python3
# This file is part of newVM.
# Copyright (C) 2026 Howard Dent
# SPDX-License-Identifier: GPL-3.0-or-later
#
# newVM is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your
# option) any later version. It is distributed WITHOUT ANY WARRANTY; see
# the file LICENSE at the top of the repository for details.

# ---------------------------------------------------------------------------
# Generates cvddata.inc for the healthKent demo: the inputs of the expected
# heart attack and stroke model (uKentData.pas's CVD section does the
# arithmetic, so the relative risks stay editable there).
#
# THE MODEL (per LSOA i, age-sex band b = 18 five-year bands x 2 sexes):
#   events_i = sum_b pop_ib * I_b * M_ib
#   I_b   England's emergency admission rate for acute MI (I21-I22) or
#         stroke (I61-I64) at that age and sex, 2024-25 (HES), per person
#         per year - the same diagnoses as OHID's Local Health indicators.
#   M_ib  the relative-risk multiplier against an average English person of
#         that age and sex:
#           prod_f (1 + p_fib (RR_f - 1)) / (1 + pbar_fb (RR_f - 1))
#         over smoking, obesity, diabetes, hypertension, CKD 3-5 and AF, times an
#         ethnicity factor and a residual deprivation factor, each likewise
#         divided by its England average.
#
# WHAT THIS SCRIPT ESTIMATES
#   - Age-sex population of each LSOA: ONS mid-2024, 5-year bands (0-4 ..
#     85+) by sex - measured.
#   - Diabetes (QOF DM, 17+), hypertension (HYP), CKD 3-5 (CKD, 18+), AF:
#     diagnosed prevalence. Across all of England's practices, register_p ~
#     Poisson( exp(beta z_p) sum_b n_pb r_b ), with n_pb the practice's
#     patients by age (April 2025; one curve for both sexes, since QOF has
#     no sex breakdown and practices' sex ratios barely vary), z_p its patients' mean IMD 2025
#     score less the national mean, and log r_b smoothed by a second-
#     difference penalty along age. r_b is the age-sex curve, beta the
#     deprivation gradient. Each practice's residual O/E is then shared out
#     to the LSOAs its patients live in (patients by LSOA, April 2025), so
#     an LSOA's prevalence in band b is
#       p_fib = r_fb * exp(beta_f z_i) * (patient-weighted residual of its practices)
#     - within-practice variation follows the LSOA's own age, sex and IMD.
#     pbar_fb is England's average at that age and sex.
#   - Smoking, current, 18+: OHID's APS figures by LSOA IMD 2025 decile
#     (England, 2023-25) times England's age and sex gradients (2025),
#     normalised so England's 18+ total is unchanged, then scaled to each
#     district's APS 2023-25 value - shrunk towards 1 (log scale, prior
#     SD SURVEY_TAU) because the district survey samples are small.
#   - Obesity (BMI 30+), 18+: the same method on Sport England's Active
#     Lives survey (OHID indicator 93881, adjusted self-reported height and
#     weight), 2024/25: England by national LSOA deprivation decile (LSOA
#     2011, IMD 2019 - the latest it has, applied to IMD 2025 deciles), age
#     and sex, scaled towards each district's 2024/25 figure.
#   - Ethnicity: Census 2021 share of South Asian (Indian, Pakistani,
#     Bangladeshi) and Black residents of each LSOA, and England's.
#   - STEMI share of MI admissions by age and sex (for the STEMI weighting):
#     HES's 4-character diagnoses split I21 into STEMI (I21.0-I21.3) and
#     NSTEMI (I21.4); I21.9 and I22 are left unassigned, so they take the
#     same share. The episodes' STEMI odds by age (ages under 35 pooled,
#     85+ pooled) times a female odds ratio from the episodes by sex, then
#     scaled by one constant so England's expected STEMI share of MI
#     admissions equals that of the emergency admissions (episodes
#     over-count NSTEMI, which more often has several consultant episodes).
#   - Check: OHID Local Health MSOA indirectly age-standardised ratios
#     for emergency admissions for MI and for stroke (2016/17-20/21),
#     combined by expected counts, for each MSOA, matched to MSOA 2021.
#
# Sources (in <download dir>/cvd/, besides the files make_kent_data.py uses):
#   pop2024_lsoa_agesex.csv   Nomis NM_2014_1, geography=<each LAD>TYPE151 (Medway's
#                             LSOAs by code: its TYPE151 query returns nothing),
#                             gender=1,2, c_age=1,3..18,210 (5-year bands), date=latest
#   pop2024_england_agesex.csv  the same for geography=E92000001
#   census2021_ts021_lsoa.csv Nomis NM_2041_1 (TS021), c2021_eth_20=0,10,11,12,1002,
#                             the 13 LADs' LSOAs and England
#   QOF2425/                  https://files.digital.nhs.uk/95/4708D7/QOF2425.zip
#                             (PREVALENCE_2425.csv)
#   gp-reg-pat-prac-lsoa-2021-male-female-Apr-25/  NHS England, Patients Registered at
#                             a GP Practice April 2025, practice x LSOA 2021
#   gp-reg-pat-prac-quin-age/ the same publication, practice x 5-year age x sex
#   hosp-epis-stat-admi-diag-2024-25.csv  NHS England, Hospital Admitted Patient Care
#                             Activity 2024-25, primary diagnosis 3 and 4 character (CSV)
#   fing_92443.csv            Fingertips API all_data/csv/by_indicator_id?indicator_ids=
#                             92443&child_area_type_id=501 (APS smoking prevalence 18+)
#   fing_93881.csv            the same for 93881 (Active Lives adult obesity)
#   fing_93232_msoa.csv, fing_93231_msoa.csv  the same for 93232 (MI) and 93231
#                             (stroke) emergency admissions, child_area_type_id=3 (MSOA)
#   lsoa_msoa21.json          ONS OA21_LAD23_LSOA21_MSOA21_LEP23_EN_LU, Kent LADs,
#                             {LSOA21CD: [MSOA21CD, MSOA21NM]}
#   msoa11_21.json            ONS MSOA11_MSOA21_LAD22_EW_LU_v2, Kent LADs (1:1 here)
#
# Usage: python3 make_cvd_data.py <download dir>
# ---------------------------------------------------------------------------
import sys, os, csv, json, math, collections
import numpy as np
from scipy.optimize import minimize

src = sys.argv[1]
cvd = os.path.join(src, 'cvd')
here = os.path.dirname(os.path.abspath(__file__))
SURVEY_TAU = 0.15           # prior SD of a district's log survey ratio (smoking, obesity)
SMOOTH = 0.01               # second-difference penalty on log r along age
NB = 18                     # age bands 0-4 .. 80-84, 85+
SEXES = ('Male', 'Female')
BAND_LO = [5 * a for a in range(NB)]
FACTORS = [('DM', 'diabetes', 17), ('HYP', 'hypertension', 18), ('CKD', 'CKD stages 3-5', 18), ('AF', 'atrial fibrillation', 18)]

def C(name):
    return os.path.join(cvd, name)

def band_weight(min_age):
    """fraction of each 5-year band at or above min_age"""
    return np.array([min(1.0, max(0.0, (lo + 5 - min_age) / 5.0)) for lo in BAND_LO])

# ---- Kent LSOAs, IMD -------------------------------------------------------------
lookup = {f['attributes']['LSOA21CD']: f['attributes'] for f in json.load(open(os.path.join(src, 'icb_lookup.json')))['features']}
codes = sorted(lookup)
idx = {c: i for i, c in enumerate(codes)}
N = len(codes)
lads = sorted({(a['LAD25CD'], a['LAD25NM']) for a in lookup.values()}, key=lambda t: t[1])
lad_index = {c: i for i, (c, _) in enumerate(lads)}
lsoa_lad = np.array([lad_index[lookup[c]['LAD25CD']] for c in codes])

imd_score, imd_decile = {}, {}
with open(os.path.join(src, 'iod2025_file7.csv'), encoding='utf-8-sig') as fh:
    r = csv.reader(fh)
    next(r)
    for row in r:
        imd_score[row[0]] = float(row[4])
        imd_decile[row[0]] = int(row[6])
k_imd = np.array([imd_score[c] for c in codes])
k_dec = np.array([imd_decile[c] for c in codes])

# ---- population by age and sex ---------------------------------------------------
AGE_CODES = [1] + list(range(3, 19)) + [210]
age_pos = {str(a): k for k, a in enumerate(AGE_CODES)}
pop = np.zeros((N, 2 * NB))
for row in csv.DictReader(open(C('pop2024_lsoa_agesex.csv'))):
    if row['GEOGRAPHY_CODE'] in idx:
        pop[idx[row['GEOGRAPHY_CODE']], SEXES.index(row['GENDER_NAME']) * NB + age_pos[row['C_AGE']]] = int(row['OBS_VALUE'])
eng = np.zeros(2 * NB)
for row in csv.DictReader(open(C('pop2024_england_agesex.csv'))):
    eng[SEXES.index(row['GENDER_NAME']) * NB + age_pos[row['C_AGE']]] = int(row['OBS_VALUE'])
assert pop.sum(axis=1).min() > 0 and eng.min() > 0

# ---- baseline: HES emergency admissions for MI and stroke --------------------------
hes = collections.defaultdict(dict)
for row in csv.DictReader(open(C('hosp-epis-stat-admi-diag-2024-25.csv'), encoding='utf-8-sig')):
    if row['Category'] == 'DIAG_3_01' and row['Code'] in ('I21', 'I22', 'I61', 'I62', 'I63', 'I64'):
        hes[row['Code']][row['Attribute']] = float(row['Value'] or 0)
HES_BANDS = [['Age_0_Sum', 'Age_1_4_Sum'], ['Age_5_9_Sum'], ['Age_10_14_Sum'],
             ['Age_15_Sum', 'Age_16_Sum', 'Age_17_Sum', 'Age_18_Sum', 'Age_19_Sum']] + \
            [['Age_%d_%d_Sum' % (lo, lo + 4)] for lo in range(20, 85, 5)] + [['Age_85_89_Sum', 'Age_90_120_Sum']]
assert len(HES_BANDS) == NB
def event_rates(codes_):
    ev = np.zeros(2 * NB)
    for c in codes_:
        h = hes[c]
        age = np.array([sum(h[k] for k in ks) for ks in HES_BANDS])
        male = h['FCE_Male_Sum'] / (h['FCE_Male_Sum'] + h['FCE_Female_Sum'])
        ev[:NB] += h['FAE_EMERGENCY_Sum'] * male * age / age.sum()
        ev[NB:] += h['FAE_EMERGENCY_Sum'] * (1 - male) * age / age.sum()
    return ev / eng
rate_mi = event_rates(['I21', 'I22'])
rate_st = event_rates(['I61', 'I62', 'I63', 'I64'])
base_rate = rate_mi + rate_st
hes_total = sum(hes[c]['FAE_EMERGENCY_Sum'] for c in hes)

# ---- STEMI share of MI admissions, by age and sex -----------------------------------
STEMI_CODES, NSTEMI_CODES = ('I21.0', 'I21.1', 'I21.2', 'I21.3'), ('I21.4',)
hes4 = collections.defaultdict(dict)
for row in csv.DictReader(open(C('hosp-epis-stat-admi-diag-2024-25.csv'), encoding='utf-8-sig')):
    if row['Category'] == 'DIAG_4_01' and row['Code'] in STEMI_CODES + NSTEMI_CODES:
        hes4[row['Code']][row['Attribute']] = float(row['Value'] or 0)
def h4sum(codes_, attr):
    return sum(hes4[c][attr] for c in codes_)
STEMI_POOL = [['Age_%d_Sum' % a for a in (15, 16, 17, 18, 19)] + ['Age_%d_%d_Sum' % (lo, lo + 4) for lo in (20, 25, 30)]] * 7 + \
             [['Age_%d_%d_Sum' % (lo, lo + 4)] for lo in range(35, 85, 5)] + [['Age_85_89_Sum', 'Age_90_120_Sum']]
assert len(STEMI_POOL) == NB
s_age = np.array([sum(h4sum(STEMI_CODES, k) for k in ks) for ks in STEMI_POOL])
n_age = np.array([sum(h4sum(NSTEMI_CODES, k) for k in ks) for ks in STEMI_POOL])
stemi_female_or = (h4sum(STEMI_CODES, 'FCE_Female_Sum') / h4sum(STEMI_CODES, 'FCE_Male_Sum')) / \
                  (h4sum(NSTEMI_CODES, 'FCE_Female_Sum') / h4sum(NSTEMI_CODES, 'FCE_Male_Sum'))
stemi_adm = h4sum(STEMI_CODES, 'FAE_EMERGENCY_Sum')
nstemi_adm = h4sum(NSTEMI_CODES, 'FAE_EMERGENCY_Sum')
odds0 = np.concatenate([s_age / n_age, s_age / n_age * stemi_female_or])
def stemi_share(c):
    return c * odds0 / (1 + c * odds0)
mi_eng = eng * rate_mi
lo_c, hi_c = 0.01, 100.0
for _ in range(100):
    mid = math.sqrt(lo_c * hi_c)
    if (mi_eng * stemi_share(mid)).sum() / mi_eng.sum() < stemi_adm / (stemi_adm + nstemi_adm):
        lo_c = mid
    else:
        hi_c = mid
stemi_c = math.sqrt(lo_c * hi_c)
stemi_sh = stemi_share(stemi_c)
print('STEMI: %d emergency admissions, NSTEMI %d (share %.3f); female OR %.3f, episode-to-admission odds x%.3f'
      % (stemi_adm, nstemi_adm, stemi_adm / (stemi_adm + nstemi_adm), stemi_female_or, stemi_c))
print('  share by band, men  ', ' '.join('%.2f' % x for x in stemi_sh[:NB]))
print('  share by band, women', ' '.join('%.2f' % x for x in stemi_sh[NB:]))

# ---- practices: list by age and sex, deprivation, QOF registers -------------------
QUIN = ['0_4', '5_9', '10_14', '15_19', '20_24', '25_29', '30_34', '35_39', '40_44', '45_49',
        '50_54', '55_59', '60_64', '65_69', '70_74', '75_79', '80_84']
qpos = {q: k for k, q in enumerate(QUIN)}
for q in ('85_89', '90_94', '95+'):
    qpos[q] = NB - 1
plist = collections.defaultdict(lambda: np.zeros(2 * NB))
for row in csv.DictReader(open(C('gp-reg-pat-prac-quin-age/gp-reg-pat-prac-quin-age.csv'))):
    if row['ORG_TYPE'] == 'GP' and row['SEX'] in ('MALE', 'FEMALE') and row['AGE_GROUP_5'] != 'ALL':
        plist[row['ORG_CODE']][(0 if row['SEX'] == 'MALE' else 1) * NB + qpos[row['AGE_GROUP_5']]] += int(row['NUMBER_OF_PATIENTS'])

prac_lsoa = collections.defaultdict(dict)       # practice -> {LSOA: patients}
for row in csv.DictReader(open(C('gp-reg-pat-prac-lsoa-2021-male-female-Apr-25/gp-reg-pat-prac-lsoa-all.csv'))):
    prac_lsoa[row['PRACTICE_CODE']][row['LSOA_CODE']] = int(row['NUMBER_OF_PATIENTS'])

reg = collections.defaultdict(dict)
for row in csv.DictReader(open(C('QOF2425/PREVALENCE_2425.csv'))):
    reg[row['PRACTICE_CODE']][row['GROUP_CODE']] = float(row['REGISTER'])

pracs = []
for p in sorted(reg):
    if p not in plist or plist[p].sum() < 500:
        continue
    known = {l: n for l, n in prac_lsoa.get(p, {}).items() if l in imd_score}
    if sum(known.values()) < 0.8 * plist[p].sum():
        continue
    z = sum(n * imd_score[l] for l, n in known.items()) / sum(known.values())
    pracs.append((p, z))
P = len(pracs)
Z = np.array([z for _, z in pracs])
Nlist = np.array([plist[p] for p, _ in pracs])
zbar = (Z * Nlist.sum(axis=1)).sum() / Nlist.sum()
Z = Z - zbar

def fit_register(group, min_age):
    """one age curve for both sexes: QOF registers have no sex breakdown, and
    practices' sex ratios vary too little to separate men from women"""
    O = np.array([reg[p].get(group, 0.0) for p, _ in pracs])
    w = band_weight(min_age)
    use = w > 0
    Npers = Nlist[:, :NB] + Nlist[:, NB:]
    Nw = Npers[:, use] * w[use]
    nb = use.sum()
    D = np.zeros((nb - 2, nb + 1))                    # second differences along age
    for k in range(nb - 2):
        D[k, k], D[k, k + 1], D[k, k + 2] = 1, -2, 1
    scale = O.sum()
    def f(x):
        th, beta = x[:nb], x[nb]
        eb = np.exp(beta * Z)
        mu = eb * (Nw @ np.exp(th))
        nll = (mu - O * np.log(mu)).sum() / scale
        g1 = (1 - O / mu)
        gth = (Nw * (g1 * eb)[:, None]).sum(axis=0) * np.exp(th) / scale
        gb = (g1 * mu * Z).sum() / scale
        pen = D @ x
        return nll + SMOOTH * (pen @ pen), np.append(gth, gb) + 2 * SMOOTH * (D.T @ pen)
    x0 = np.append(np.full(nb, math.log(O.sum() / Nw.sum())), 0.0)
    res = minimize(f, x0, jac=True, method='L-BFGS-B', options=dict(maxiter=5000))
    assert res.success, res.message
    th, beta = res.x[:nb], res.x[nb]
    r1 = np.zeros(NB); r1[use] = np.exp(th) * w[use]   # per head of the whole band
    r = np.tile(r1, 2)
    eb = np.exp(beta * Z)
    E = eb * (Nlist @ r)
    resid = O / E
    pbar = (Nlist * eb[:, None]).sum(axis=0) * r / Nlist.sum(axis=0)
    return r, beta, dict(zip([p for p, _ in pracs], resid)), pbar, O.sum() / E.sum()

# share of each Kent LSOA's registered patients by practice
lsoa_prac = collections.defaultdict(dict)
for p, ls in prac_lsoa.items():
    for l, n in ls.items():
        if l in idx:
            lsoa_prac[l][p] = n

prev_rate, prev_scale, prev_nat, betas, coverage = [], [], [], [], []
for g, nm, mn in FACTORS:
    r, beta, resid, pbar, oe = fit_register(g, mn)
    sc = np.zeros(N)
    cov = np.zeros(N)
    for l, i in idx.items():
        ps = lsoa_prac[l]
        tot = sum(ps.values())
        known = {p: n for p, n in ps.items() if p in resid}
        kn = sum(known.values())
        cov[i] = kn / tot if tot else 0
        rr = sum(n * resid[p] for p, n in known.items()) / kn if kn else 1.0
        sc[i] = math.exp(beta * (k_imd[i] - zbar)) * rr
    prev_rate.append(r); prev_scale.append(sc); prev_nat.append(pbar); betas.append(beta); coverage.append(cov)
    kent = (pop * r * sc[:, None]).sum()
    print('%-4s beta %.4f per IMD point, overall O/E %.3f; Kent expected %d diagnosed (%.2f %% of all ages)'
          % (g, beta, oe, kent, 100 * kent / pop.sum()))
    print('     r per 1000:', ' '.join('%.0f' % (1000 * v) for v in r[:NB]))

# ---- smoking -----------------------------------------------------------------------
fing = list(csv.DictReader(open(C('fing_92443.csv'))))
DEC_NAMES = ['Most deprived decile', 'Second most deprived decile', 'Third more deprived decile',
             'Fourth more deprived decile', 'Fifth more deprived decile', 'Fifth less deprived decile',
             'Fourth less deprived decile', 'Third less deprived decile', 'Second least deprived decile',
             'Least deprived decile']
SMOKE_PERIOD = '2023 - 25'
dec_rate = {}
for row in fing:
    if row['Time period'] == SMOKE_PERIOD and row['Sex'] == 'Persons' and row['Age'] == '18+ yrs' \
       and row['Category Type'] == 'LSOA21 deprivation deciles in England (IMD2025)':
        dec_rate[DEC_NAMES.index(row['Category']) + 1] = float(row['Value']) / 100
assert len(dec_rate) == 10
def eng_value(period, sex, age):
    for row in fing:
        if row['Time period'] == period and row['Area Type'] == 'England' and row['Sex'] == sex \
           and row['Age'] == age and row['Category'] == '':
            return float(row['Value']) / 100
    return None
AGE_P = '2025'
all18 = eng_value(AGE_P, 'Persons', '18+ yrs')
sex_f = [eng_value(AGE_P, s, '18+ yrs') / all18 for s in SEXES]
age_f = np.zeros(NB)
y18 = (eng_value(AGE_P, 'Male', '18-24 yrs') * eng[4] + eng_value(AGE_P, 'Female', '18-24 yrs') * eng[NB + 4]) / (eng[4] + eng[NB + 4])
age_f[3] = 0.4 * y18 / all18             # 15-19: 18 and 19 only
age_f[4] = y18 / all18
for k in range(5, 17):
    age_f[k] = eng_value(AGE_P, 'Persons', '%d-%d yrs' % (5 * k, 5 * k + 4)) / all18
age_f[17] = (eng_value(AGE_P, 'Persons', '85-89 yrs') * 0.6 + eng_value(AGE_P, 'Persons', '90+ yrs') * 0.4) / all18
smoke_as = np.concatenate([age_f * sex_f[0], age_f * sex_f[1]])
adult = np.concatenate([band_weight(18)] * 2)
smoke_as /= (eng * smoke_as).sum() / (eng * adult).sum()      # England's 18+ mean factor = 1
smoke_base = np.array([dec_rate[d] for d in k_dec])
# district calibration: each district's survey figure, shrunk towards the
# decile model's prediction for it (log scale, prior SD SURVEY_TAU)
def calibrate(label, rows, period, base, as_):
    pred = np.zeros(len(lads)); ad = np.zeros(len(lads))
    for i in range(N):
        pred[lsoa_lad[i]] += (pop[i] * as_).sum() * base[i]
        ad[lsoa_lad[i]] += (pop[i] * adult).sum()
    vals, facs = [], []
    for d, (lc, ln) in enumerate(lads):
        row = next(r for r in rows if r['Time period'] == period and r['Area Code'] == lc and r['Sex'] == 'Persons'
                   and r['Age'] == '18+ yrs' and r['Category'] == '')
        v, lo, hi = float(row['Value']) / 100, float(row['Lower CI 95.0 limit']) / 100, float(row['Upper CI 95.0 limit']) / 100
        se = (math.log(hi) - math.log(lo)) / (2 * 1.96)
        m = pred[d] / ad[d]
        w = SURVEY_TAU ** 2 / (SURVEY_TAU ** 2 + se ** 2)
        fac = math.exp(w * math.log(v / m))
        vals.append(v); facs.append(fac)
        print('%-8s %-22s survey %4.1f %% (%4.1f-%4.1f), decile model %4.1f %%, weight %.2f, factor %.3f'
              % (label, ln, 100 * v, 100 * lo, 100 * hi, 100 * m, w, fac))
    return vals, facs, base * np.array([facs[d] for d in lsoa_lad])

dist_aps, dist_fac, smoke_lsoa = calibrate('smoking', fing, SMOKE_PERIOD, smoke_base, smoke_as)
smoke_eng = eng_value(SMOKE_PERIOD, 'Persons', '18+ yrs')
print('England 18+ smoking %s: %.2f %%; Kent model %.2f %%' % (SMOKE_PERIOD, 100 * smoke_eng, 100 * (pop * smoke_as * smoke_lsoa[:, None]).sum() / (pop * adult).sum()))

# ---- obesity (Active Lives, BMI 30+ from adjusted self-reported height and weight) ----
obes = list(csv.DictReader(open(C('fing_93881.csv'))))
OBES_PERIOD = '2024/25'
def ob_value(sex, age, cat=''):
    for row in obes:
        if row['Time period'] == OBES_PERIOD and row['Area Type'] == 'England' and row['Sex'] == sex \
           and row['Age'] == age and row['Category'] == cat:
            return float(row['Value']) / 100
    return None
# national deciles of LSOA 2011 by IMD 2019 - the latest Active Lives has; applied
# here to each LSOA's IMD 2025 decile
ob_dec = {}
for row in obes:
    if row['Time period'] == OBES_PERIOD and row['Area Type'] == 'England' and row['Sex'] == 'Persons' \
       and row['Age'] == '18+ yrs' and row['Category Type'].startswith('LSOA11 deprivation deciles'):
        ob_dec[DEC_NAMES.index(row['Category']) + 1] = float(row['Value']) / 100
assert len(ob_dec) == 10
ob_all = ob_value('Persons', '18+ yrs')
ob_age = np.zeros(NB)
OB_AGES = [('18-24 yrs', [3, 4]), ('25-34 yrs', [5, 6]), ('35-44 yrs', [7, 8]), ('45-54 yrs', [9, 10]),
           ('55-64 yrs', [11, 12]), ('65-74 yrs', [13, 14]), ('75-84 yrs', [15, 16]), ('85+ yrs', [17])]
for age, ks in OB_AGES:
    for k in ks:
        ob_age[k] = ob_value('Persons', age) / ob_all
ob_age[3] *= 0.4                          # 15-19: 18 and 19 only
ob_sex = [ob_value(s_, '18+ yrs') / ob_all for s_ in SEXES]
ob_as = np.concatenate([ob_age * ob_sex[0], ob_age * ob_sex[1]])
ob_as /= (eng * ob_as).sum() / (eng * adult).sum()
dist_ob, dist_obfac, ob_lsoa = calibrate('obesity', obes, OBES_PERIOD, np.array([ob_dec[d] for d in k_dec]), ob_as)
print('England 18+ obesity %s: %.2f %%; Kent model %.2f %%' % (OBES_PERIOD, 100 * ob_all,
      100 * (pop * ob_as * ob_lsoa[:, None]).sum() / (pop * adult).sum()))

# ---- ethnicity -----------------------------------------------------------------------
eth = collections.defaultdict(dict)
for row in csv.DictReader(open(C('census2021_ts021_lsoa.csv'))):
    eth[row['GEOGRAPHY_CODE']][row['C2021_ETH_20']] = int(row['OBS_VALUE'])
def shares(e):
    return (e['10'] + e['11'] + e['12']) / e['0'], e['1002'] / e['0']
sa = np.array([shares(eth[c])[0] for c in codes])
bl = np.array([shares(eth[c])[1] for c in codes])
sa_eng, bl_eng = shares(eth['E92000001'])

# ---- MSOAs and the observed ratios -------------------------------------------------------
lm = json.load(open(C('lsoa_msoa21.json')))
m21_11 = {f['attributes']['MSOA21CD']: f['attributes']['MSOA11CD'] for f in json.load(open(C('msoa11_21.json')))['features']}
msoas = sorted({tuple(lm[c]) for c in codes}, key=lambda t: t[1])
mpos = {m[0]: k for k, m in enumerate(msoas)}
lsoa_msoa = np.array([mpos[lm[c][0]] for c in codes])
def sar(fn):
    out = {}
    for row in csv.DictReader(open(C(fn))):
        if row['Area Type'] == 'MSOA' and row['Value']:
            out[row['Area Code']] = float(row['Value']) / 100
    return out
s_mi, s_st = sar('fing_93232_msoa.csv'), sar('fing_93231_msoa.csv')
m_obs, m_name, m_hoc = [], [], {}
for row in csv.DictReader(open(C('fing_93232_msoa.csv'))):
    m_hoc[row['Area Code']] = row['Area Name']
for k, (m21, nm) in enumerate(msoas):
    e_mi = sum((pop[i] * rate_mi).sum() for i in range(N) if lsoa_msoa[i] == k)
    e_st = sum((pop[i] * rate_st).sum() for i in range(N) if lsoa_msoa[i] == k)
    m11 = m21_11.get(m21, m21)
    if m11 in s_mi and m11 in s_st:
        m_obs.append((s_mi[m11] * e_mi + s_st[m11] * e_st) / (e_mi + e_st))
    else:
        m_obs.append(float('nan'))
    m_name.append(m_hoc.get(m11, ''))

# ---- quick check of the default relative risks (the Pascal side does it properly) ---------
RR = dict(obese=1.2, smoke=2.0, DM=2.0, HYP=1.6, CKD=1.4, AF=1.5, SA=1.4, BL=0.75, DEP=1.3)
M = np.ones((N, 2 * NB))
def mult(p, pbar, rr):
    return (1 + np.minimum(p, 1) * (rr - 1)) / (1 + pbar * (rr - 1))
M *= mult(smoke_lsoa[:, None] * smoke_as[None, :], smoke_eng * smoke_as[None, :], RR['smoke'])
M *= mult(ob_lsoa[:, None] * ob_as[None, :], ob_all * ob_as[None, :], RR['obese'])
for k, (g, _, _) in enumerate(FACTORS):
    M *= mult(prev_rate[k][None, :] * prev_scale[k][:, None], prev_nat[k][None, :], RR[g])
M *= ((1 + sa * (RR['SA'] - 1) + bl * (RR['BL'] - 1)) / (1 + sa_eng * (RR['SA'] - 1) + bl_eng * (RR['BL'] - 1)))[:, None]
dep = np.exp(math.log(RR['DEP']) * (5.5 - k_dec) / 9)
M *= (dep / np.mean(np.exp(math.log(RR['DEP']) * (5.5 - np.arange(1, 11)) / 9)))[:, None]
ev = (pop * base_rate * M).sum(axis=1)
e0 = (pop * base_rate).sum(axis=1)
me, m0 = np.zeros(len(msoas)), np.zeros(len(msoas))
np.add.at(me, lsoa_msoa, ev); np.add.at(m0, lsoa_msoa, e0)
ok = ~np.isnan(np.array(m_obs))
mod, obs = (me / m0)[ok], np.array(m_obs)[ok]
print('Kent: %.0f expected admissions/year (age and sex only %.0f); SAR %.3f' % (ev.sum(), e0.sum(), ev.sum() / e0.sum()))
print('MSOA check: %d MSOAs, r(model SAR, observed SAR) = %.3f; observed Kent SAR %.3f'
      % (ok.sum(), np.corrcoef(mod, obs)[0, 1], (obs * m0[ok]).sum() / m0[ok].sum()))
print('  r(IMD-only) = %.3f' % np.corrcoef(np.bincount(lsoa_msoa, weights=k_imd * pop.sum(1))[ok] / np.bincount(lsoa_msoa, weights=pop.sum(1))[ok], obs)[0, 1])

# ---- write -------------------------------------------------------------------------------
def pas(s):
    return "'" + s.replace("'", "''") + "'"

def arr(name, typ, vals, fmt, per=10):
    items = [fmt % v for v in vals]
    lines = [', '.join(items[i:i + per]) for i in range(0, len(items), per)]
    return '  %s: array[0..%d] of %s = (\n    %s\n  );\n' % (name, len(vals) - 1, typ, ',\n    '.join(lines))

with open(os.path.join(here, 'cvddata.inc'), 'w', encoding='utf-8') as fh:
    fh.write('// Generated by make_cvd_data.py - do not edit. Inputs of the expected heart\n'
             '// attack and stroke admissions model; see that script and uKentData.pas.\n'
             '// Band b = sex * CvdBandCount + age band (0 male, 1 female; 0-4 .. 80-84, 85+).\n')
    fh.write('const\n  CvdBandCount = %d;\n  CvdFactorCount = %d;\n  MsoaCount = %d;\n'
             % (NB, len(FACTORS), len(msoas)))
    fh.write('  CvdHesYear = %s;\n  CvdQofYear = %s;\n  CvdSmokePeriod = %s;\n'
             % (pas('2024-25'), pas('2024-25'), pas(SMOKE_PERIOD.replace(' ', ''))))
    fh.write('  CvdHesEnglandAdmissions = %d;\n' % round(hes_total))
    fh.write('  CvdSouthAsianEngland = %.6f;\n  CvdBlackEngland = %.6f;\n  CvdSurveyTau = %.3f;\n'
             % (sa_eng, bl_eng, SURVEY_TAU))
    fh.write(arr('CvdFactorCode', 'string', [pas(g) for g, _, _ in FACTORS], '%s', 4))
    fh.write(arr('CvdFactorName', 'string', [pas(n) for _, n, _ in FACTORS], '%s', 4))
    fh.write(arr('CvdFactorBeta', 'Double', betas, '%.6f', 4))
    fh.write('  // England emergency admissions per person per year (MI I21-I22, stroke I61-I64)\n')
    fh.write(arr('CvdRateMI', 'Double', rate_mi, '%.6e', 6))
    fh.write(arr('CvdRateStroke', 'Double', rate_st, '%.6e', 6))
    fh.write('  // STEMI share of MI admissions at that age and sex (HES 4-character diagnoses)\n')
    fh.write('  CvdStemiAdmissions = %d;\n  CvdNstemiAdmissions = %d;\n  CvdStemiFemaleOR = %.3f;\n'
             % (round(stemi_adm), round(nstemi_adm), stemi_female_or))
    fh.write(arr('CvdStemiShare', 'Double', stemi_sh, '%.4f', 9))
    fh.write(arr('CvdEnglandPop', 'Integer', eng, '%d', 9))
    fh.write('  // LSOA i, band b: LsoaAgePop[i * 2 * CvdBandCount + b]\n')
    fh.write(arr('LsoaAgePop', 'Integer', pop.ravel(), '%d', 18))
    fh.write('  // factor f, band b: diagnosed prevalence at England''s mean IMD, and England''s average\n')
    fh.write(arr('CvdPrevRate', 'Double', np.concatenate(prev_rate), '%.6e', 6))
    fh.write(arr('CvdPrevEngland', 'Double', np.concatenate(prev_nat), '%.6e', 6))
    fh.write('  // LSOA i, factor f: CvdPrevScale[i * CvdFactorCount + f] (deprivation and practice residual)\n')
    fh.write(arr('CvdPrevScale', 'Single', np.array(prev_scale).T.ravel(), '%.4f', 12))
    fh.write(arr('CvdPracticeCoverage', 'Single', coverage[0], '%.3f', 12))
    fh.write('  // smoking: band factor (England 18+ mean 1) and each LSOA''s 18+ rate before it\n')
    fh.write(arr('CvdSmokeBand', 'Double', smoke_as, '%.6f', 6))
    fh.write('  CvdSmokeEngland = %.5f;\n' % smoke_eng)
    fh.write(arr('CvdSmokeDecile', 'Double', [dec_rate[d] for d in range(1, 11)], '%.5f', 10))
    fh.write(arr('CvdSmokeLsoa', 'Single', smoke_lsoa, '%.5f', 12))
    fh.write(arr('DistrictSmokeAPS', 'Single', dist_aps, '%.4f', 13))
    fh.write(arr('DistrictSmokeFactor', 'Single', dist_fac, '%.4f', 13))
    fh.write('  // obesity (Active Lives %s): band factor, England 18+, each LSOA''s 18+ rate\n' % OBES_PERIOD)
    fh.write('  CvdObesityPeriod = %s;\n' % pas(OBES_PERIOD))
    fh.write('  CvdObesityEngland = %.5f;\n' % ob_all)
    fh.write(arr('CvdObesityBand', 'Double', ob_as, '%.6f', 6))
    fh.write(arr('CvdObesityDecile', 'Double', [ob_dec[d] for d in range(1, 11)], '%.5f', 10))
    fh.write(arr('CvdObesityLsoa', 'Single', ob_lsoa, '%.5f', 12))
    fh.write(arr('DistrictObesitySurvey', 'Single', dist_ob, '%.4f', 13))
    fh.write(arr('DistrictObesityFactor', 'Single', dist_obfac, '%.4f', 13))
    fh.write(arr('LsoaSouthAsian', 'Single', sa, '%.5f', 12))
    fh.write(arr('LsoaBlack', 'Single', bl, '%.5f', 12))
    fh.write(arr('LsoaMsoa', 'Integer', lsoa_msoa, '%d', 20))
    fh.write(arr('MsoaCode', 'string', [pas(m[0]) for m in msoas], '%s', 6))
    fh.write(arr('MsoaName', 'string', [pas(m[1]) for m in msoas], '%s', 5))
    fh.write(arr('MsoaLocalName', 'string', [pas(n) for n in m_name], '%s', 3))
    fh.write('  // observed emergency admission SAR, MI and stroke combined, 2016/17-20/21 (NaN: none)\n')
    fh.write(arr('MsoaObservedSAR', 'Double', [v if v == v else -1 for v in m_obs], '%.4f', 10))
print('wrote cvddata.inc: %d LSOAs, %d MSOAs' % (N, len(msoas)))
