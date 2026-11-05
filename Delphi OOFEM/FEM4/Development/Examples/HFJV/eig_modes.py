"""The system's modes near a frequency, from hfjvrun's shift-invert
Krylov basis: hfjvrun --eigdump=<prefix> --eig=<Hz> [--krylov=<m>].

OP = (i w0 E - A)^-1 E, so a Ritz value nu of the Arnoldi matrix H gives
the eigenvalue lambda = i w0 - 1/nu of E x' = A x, and the mode
x = V y. Each mode is checked by its residual |A x - lambda E x| / |A x|
and labelled by what moves: the volume it sweeps at the anterior wall
and at the diaphragm per mm of peak displacement, the share of the
moving surfaces' displacement that is on the wall, and the lung volume.

Usage: python3 eig_modes.py <prefix> <Hz> [--fmax=<Hz>] [--vtk=<f_n>]
"""
import sys, struct
import numpy as np, scipy.sparse as sp


def load_triplets(pre):
    with open(pre + '.txt') as fh:
        N = int(fh.readline().split()[1])
    raw = np.loadtxt(pre + '.txt', skiprows=1, dtype=str)
    M = {}
    for m in 'EA':
        q = raw[raw[:, 0] == m]
        M[m] = sp.csr_matrix((q[:, 3].astype(float), (q[:, 1].astype(int), q[:, 2].astype(int))),
                             shape=(N, N))
    return M['E'], M['A']


def main():
    opts = dict(a[2:].split('=', 1) for a in sys.argv[1:] if a.startswith('--'))
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    pre, f0 = args[0], float(args[1])
    E, A = load_triplets(pre)
    with open(pre + '_dofs.txt') as fh:
        t = fh.readline().split()
        idx = {t[k]: int(t[k + 1]) for k in range(0, len(t), 2)}
        t = fh.readline().split()
        eb, nm = int(t[1]), int(t[3])
    mv = np.loadtxt(pre + '_dofs.txt', skiprows=2)
    ww, wd = mv[:, 2], mv[:, 3]
    onwall = ww != 0

    with open('%s_kry%.2f.bin' % (pre, f0), 'rb') as fh:
        N, m = struct.unpack('<ii', fh.read(8))
        (fs,) = struct.unpack('<d', fh.read(8))
        H = np.frombuffer(fh.read(16 * (m + 1) * m), dtype='<f8').view(complex).reshape(m + 1, m)
        # each vector is N real parts, then N imaginary parts
        R = np.frombuffer(fh.read(16 * N * m), dtype='<f8').reshape(m, 2, N)
        V = (R[:, 0, :] + 1j * R[:, 1, :]).T
    nu, Y = np.linalg.eig(H[:m, :m])
    w0 = 2 * np.pi * fs
    lam = 1j * w0 - 1 / nu
    fmax = float(opts.get('fmax', 2 * fs))

    print('Modes of E x\' = A x from %d Krylov vectors about %.2f Hz (%d unknowns)' % (m, fs, N))
    print('Volumes per mm of peak surface displacement; wall share of the surfaces\' displacement')
    print('   f_n Hz   f_d Hz    zeta       Q     resid   V_wall mL  V_dia mL  wall %  V_lung mL')
    out = []
    for k in range(m):
        l = lam[k]
        if l.imag <= 0 or l.imag / 2 / np.pi > fmax:
            continue
        x = V @ Y[:, k]
        Ax, Ex = A @ x, E @ x
        res = np.linalg.norm(Ax - l * Ex) / np.linalg.norm(Ax)
        eta = x[eb:eb + nm]
        s = np.max(np.abs(eta)) * 1e3      # per mm peak
        x = x / s
        eta = eta / s
        Vw, Vd = ww @ eta, wd @ eta
        VL = x[idx['iVrc']] + Vd
        share = np.sum(np.abs(eta[onwall]) ** 2) / np.sum(np.abs(eta) ** 2)
        fn = abs(l) / 2 / np.pi
        z = -l.real / abs(l)
        out.append((fn, l.imag / 2 / np.pi, z, 1 / (2 * z) if z > 0 else np.inf, res,
                    1e6 * abs(Vw), 1e6 * abs(Vd), 100 * share, 1e6 * abs(VL), x))
    for r in sorted(out, key=lambda r: r[0]):
        flag = '' if r[4] < 1e-6 else '  (not converged)'
        print('%8.3f %8.3f %8.4f %7.2f  %8.1e  %9.2f %9.2f %6.0f %10.2f%s' % (r[:9] + (flag,)))


if __name__ == '__main__':
    main()
