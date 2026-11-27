"""Modelo de referência do AES-128 (FIPS-197) e dos modos do MiniSoC AES.

Blocos e chaves são inteiros de 128 bits, com o byte 0 no MSB, a mesma
convenção do RTL. Executar este arquivo confere o modelo contra os
vetores da FIPS-197 (Apêndices B e C.1) e da SP 800-38A (F.1.1, F.2.1).
"""

# ==========================================================
# S-box
# ==========================================================
def _xtime(b):
    b <<= 1
    return (b ^ 0x11B) & 0xFF if b & 0x100 else b


def _gmul(a, b):
    r = 0
    while b:
        if b & 1:
            r ^= a
        a = _xtime(a)
        b >>= 1
    return r


def _build_sbox():
    sbox = [0] * 256
    for x in range(256):
        inv = 0 if x == 0 else next(y for y in range(1, 256) if _gmul(x, y) == 1)
        s = inv
        for i in range(1, 5):
            s ^= ((inv << i) | (inv >> (8 - i))) & 0xFF
        sbox[x] = s ^ 0x63
    inv_sbox = [0] * 256
    for x, s in enumerate(sbox):
        inv_sbox[s] = x
    return sbox, inv_sbox


SBOX, INV_SBOX = _build_sbox()
RCON = [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1B, 0x36]


# ==========================================================
# Transformações (estado = lista de 16 bytes, byte n = s[n % 4][n // 4])
# ==========================================================
def _to_bytes(x):
    return list(x.to_bytes(16, "big"))


def _to_int(b):
    return int.from_bytes(bytes(b), "big")


def _sub_bytes(s, box):
    return [box[b] for b in s]


def _shift_rows(s, inv=False):
    out = [0] * 16
    for c in range(4):
        for r in range(4):
            src = (c - r) % 4 if inv else (c + r) % 4
            out[4 * c + r] = s[4 * src + r]
    return out


def _mix_columns(s, inv=False):
    m = [0x0E, 0x0B, 0x0D, 0x09] if inv else [0x02, 0x03, 0x01, 0x01]
    out = [0] * 16
    for c in range(4):
        col = s[4 * c:4 * c + 4]
        for r in range(4):
            v = 0
            for k in range(4):
                v ^= _gmul(m[(k - r) % 4], col[k])
            out[4 * c + r] = v
    return out


def _xor(a, b):
    return [x ^ y for x, y in zip(a, b)]


# ==========================================================
# Expansão de chave e primitivos
# ==========================================================
def key_expansion(key):
    """Retorna as 11 round keys como inteiros de 128 bits."""
    w = [_to_bytes(key)[4 * i:4 * i + 4] for i in range(4)]
    for i in range(4, 44):
        t = list(w[i - 1])
        if i % 4 == 0:
            t = [SBOX[b] for b in t[1:] + t[:1]]
            t[0] ^= RCON[i // 4 - 1]
        w.append(_xor(w[i - 4], t))
    return [_to_int(sum(w[4 * r:4 * r + 4], [])) for r in range(11)]


def encrypt_block(key, block):
    rk = [_to_bytes(k) for k in key_expansion(key)]
    s = _xor(_to_bytes(block), rk[0])
    for r in range(1, 11):
        s = _shift_rows(_sub_bytes(s, SBOX))
        if r != 10:
            s = _mix_columns(s)
        s = _xor(s, rk[r])
    return _to_int(s)


def decrypt_block(key, block):
    rk = [_to_bytes(k) for k in key_expansion(key)]
    s = _xor(_to_bytes(block), rk[10])
    for r in range(1, 11):
        s = _sub_bytes(_shift_rows(s, inv=True), INV_SBOX)
        s = _xor(s, rk[10 - r])
        if r != 10:
            s = _mix_columns(s, inv=True)
    return _to_int(s)


# ==========================================================
# Modos de operação (Block Guide, seção 8.2)
# ==========================================================
MODE_ECB, MODE_CBC, MODE_PCBC, MODE_CFB, MODE_OFB, MODE_CTR = range(6)
MASK64 = (1 << 64) - 1


def run_mode(mode, decrypt, key, iv, counter, blocks):
    """Processa a lista de blocos como o minisoc_aes_top."""
    out = []
    chain = iv
    ctr = counter & MASK64
    for b in blocks:
        if mode == MODE_ECB:
            o = decrypt_block(key, b) if decrypt else encrypt_block(key, b)
        elif mode == MODE_CBC:
            if decrypt:
                o = decrypt_block(key, b) ^ chain
                chain = b
            else:
                o = encrypt_block(key, b ^ chain)
                chain = o
        elif mode == MODE_PCBC:
            if decrypt:
                o = decrypt_block(key, b) ^ chain
            else:
                o = encrypt_block(key, b ^ chain)
            chain = b ^ o
        elif mode == MODE_CFB:
            o = b ^ encrypt_block(key, chain)
            chain = b if decrypt else o
        elif mode == MODE_OFB:
            chain = encrypt_block(key, chain)
            o = b ^ chain
        elif mode == MODE_CTR:
            o = b ^ encrypt_block(key, iv ^ ctr)
            ctr = (ctr + 1) & MASK64
        else:
            raise ValueError(f"MODE reservado: {mode}")
        out.append(o)
    return out


# ==========================================================
# Autoteste
# ==========================================================
def _selftest():
    # FIPS-197, Apêndices B e C.1
    k, p, c = 0x2B7E151628AED2A6ABF7158809CF4F3C, 0x3243F6A8885A308D313198A2E0370734, 0x3925841D02DC09FBDC118597196A0B32
    assert encrypt_block(k, p) == c and decrypt_block(k, c) == p
    assert key_expansion(k)[10] == 0xD014F9A8C9EE2589E13F0CC8B6630CA6
    k, p, c = 0x000102030405060708090A0B0C0D0E0F, 0x00112233445566778899AABBCCDDEEFF, 0x69C4E0D86A7B0430D8CDB78070B4C55A
    assert encrypt_block(k, p) == c and decrypt_block(k, c) == p

    # SP 800-38A: F.1.1 (ECB) e F.2.1 (CBC), dois primeiros blocos
    k = 0x2B7E151628AED2A6ABF7158809CF4F3C
    pt = [0x6BC1BEE22E409F96E93D7E117393172A, 0xAE2D8A571E03AC9C9EB76FAC45AF8E51]
    assert run_mode(MODE_ECB, 0, k, 0, 0, pt) == [0x3AD77BB40D7A3660A89ECAF32466EF97, 0xF5D3D58503B9699DE785895A96FDBAAF]
    iv = 0x000102030405060708090A0B0C0D0E0F
    ct = run_mode(MODE_CBC, 0, k, iv, 0, pt)
    assert ct == [0x7649ABAC8119B246CEE98E9B12E9197D, 0x5086CB9B507219EE95DB113A917678B2]
    assert run_mode(MODE_CBC, 1, k, iv, 0, ct) == pt

    # CTR: cifrar e decifrar são a mesma operação
    ct = run_mode(MODE_CTR, 0, k, iv, MASK64, pt)  # contador dá a volta
    assert run_mode(MODE_CTR, 1, k, iv, MASK64, ct) == pt
    print("aes_ref: autoteste OK")


if __name__ == "__main__":
    _selftest()
