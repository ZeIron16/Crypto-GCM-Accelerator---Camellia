-- Implementation based on the one provided by Pr. Pacalet for AES

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package gcm_pkg is

    subtype camellia_w8_t is std_ulogic_vector(0 to 7);
    subtype camellia_w64_t is std_ulogic_vector(0 to 63);
    subtype camellia_w32_t is std_ulogic_vector(0 to 31);
    subtype camellia_w128_t is std_ulogic_vector(0 to 127);

    function camellia_f(x: camellia_w64_t; k: camellia_w64_t) return camellia_w64_t;
    function camellia_fl(x: camellia_w64_t; kl: camellia_w64_t) return camellia_w64_t;
    function camellia_fl_inv(y: camellia_w64_t; kl: camellia_w64_t) return camellia_w64_t;
    function camellia_key_sched(k: camellia_w128_t) return camellia_w128_t;
    function rotate_left128(v: camellia_w128_t; n: natural) return camellia_w128_t;

    function encr_camellia128 (M, K: camellia_w128_t) return camellia_w128_t;

end package gcm_pkg;

package body gcm_pkg is

    type camellia_sbox_t is array (natural range 0 to 255) of camellia_w8_t;

    constant camellia_s1: camellia_sbox_t := (
        x"70", x"82", x"2C", x"EC", x"B3", x"27", x"C0", x"E5", x"E4", x"85", x"57", x"35", x"EA", x"0C", x"AE", x"41",
        x"23", x"EF", x"6B", x"93", x"45", x"19", x"A5", x"21", x"ED", x"0E", x"4F", x"4E", x"1D", x"65", x"92", x"BD",
        x"86", x"B8", x"AF", x"8F", x"7C", x"EB", x"1F", x"CE", x"3E", x"30", x"DC", x"5F", x"5E", x"C5", x"0B", x"1A",
        x"A6", x"E1", x"39", x"CA", x"D5", x"47", x"5D", x"3D", x"D9", x"01", x"5A", x"D6", x"51", x"56", x"6C", x"4D",
        x"8B", x"0D", x"9A", x"66", x"FB", x"CC", x"B0", x"2D", x"74", x"12", x"2B", x"20", x"F0", x"B1", x"84", x"99",
        x"DF", x"4C", x"CB", x"C2", x"34", x"7E", x"76", x"05", x"6D", x"B7", x"A9", x"31", x"D1", x"17", x"04", x"D7",
        x"14", x"58", x"3A", x"61", x"DE", x"1B", x"11", x"1C", x"32", x"0F", x"9C", x"16", x"53", x"18", x"F2", x"22",
        x"FE", x"44", x"CF", x"B2", x"C3", x"B5", x"7A", x"91", x"24", x"08", x"E8", x"A8", x"60", x"FC", x"69", x"50",
        x"AA", x"D0", x"A0", x"7D", x"A1", x"89", x"62", x"97", x"54", x"5B", x"1E", x"95", x"E0", x"FF", x"64", x"D2",
        x"10", x"C4", x"00", x"48", x"A3", x"F7", x"75", x"DB", x"8A", x"03", x"E6", x"DA", x"09", x"3F", x"DD", x"94",
        x"87", x"5C", x"83", x"02", x"CD", x"4A", x"90", x"33", x"73", x"67", x"F6", x"F3", x"9D", x"7F", x"BF", x"E2",
        x"52", x"9B", x"D8", x"26", x"C8", x"37", x"C6", x"3B", x"81", x"96", x"6F", x"4B", x"13", x"BE", x"63", x"2E",
        x"E9", x"79", x"A7", x"8C", x"9F", x"6E", x"BC", x"8E", x"29", x"F5", x"F9", x"B6", x"2F", x"FD", x"B4", x"59",
        x"78", x"98", x"06", x"6A", x"E7", x"46", x"71", x"BA", x"D4", x"25", x"AB", x"42", x"88", x"A2", x"8D", x"FA",
        x"72", x"07", x"B9", x"55", x"F8", x"EE", x"AC", x"0A", x"36", x"49", x"2A", x"68", x"3C", x"38", x"F1", x"A4",
        x"40", x"28", x"D3", x"7B", x"BB", x"C9", x"43", x"C1", x"15", x"E3", x"AD", x"F4", x"77", x"C7", x"80", x"9E"
    );

    -- Utility functions

    function rotate_left(v: camellia_w8_t) return camellia_w8_t is
    begin
        return v(1 to 7) & v(0);
    end function rotate_left;

    function rotate_right(v: camellia_w8_t) return camellia_w8_t is
    begin
        return v(7) & v(0 to 6);
    end function rotate_right;

    function rotate_left32(v: camellia_w32_t) return camellia_w32_t is
    begin
        return v(1 to 31) & v(0);
    end function rotate_left32;

    function rotate_left128(v: camellia_w128_t; n: natural) return camellia_w128_t is
    begin
        return v(n to 127) & v(0 to n-1);
    end function rotate_left128;

    -- S-box functions 

    function camellia_sbox1(v: camellia_w8_t) return camellia_w8_t is
    begin
        return camellia_s1(to_integer(v));
    end function camellia_sbox1;

    function camellia_sbox2(v: camellia_w8_t) return camellia_w8_t is
    begin
        return rotate_left(camellia_s1(to_integer(v)));
    end function camellia_sbox2;

    function camellia_sbox3(v: camellia_w8_t) return camellia_w8_t is
    begin
        return rotate_right(camellia_s1(to_integer(v)));
    end function camellia_sbox3;

    function camellia_sbox4(v: camellia_w8_t) return camellia_w8_t is
    begin
        return camellia_s1(to_integer(rotate_left(v)));
    end function camellia_sbox4;

    -- F functions
    
    function camellia_f(x: camellia_w64_t; k: camellia_w64_t) return camellia_w64_t is
        variable y: camellia_w64_t;
        variable z1,z2,z3,z4,z5,z6,z7,z8: camellia_w8_t;
        variable r1,r2,r3,r4,r5,r6,r7,r8: camellia_w8_t;
    begin
        y := x xor k;
        z1 := camellia_sbox1(y(0 to  7));
        z2 := camellia_sbox2(y(8 to 15));
        z3 := camellia_sbox3(y(16 to 23));
        z4 := camellia_sbox4(y(24 to 31));
        z5 := camellia_sbox2(y(32 to 39));
        z6 := camellia_sbox3(y(40 to 47));
        z7 := camellia_sbox4(y(48 to 55));
        z8 := camellia_sbox1(y(56 to 63));

        r1 := z1 xor z3 xor z4 xor z6 xor z7 xor z8;
        r2 := z1 xor z2 xor z4 xor z5 xor z7 xor z8;
        r3 := z1 xor z2 xor z3 xor z5 xor z6 xor z8;
        r4 := z2 xor z3 xor z4 xor z5 xor z6 xor z7;
        r5 := z1 xor z2 xor z6 xor z7 xor z8;
        r6 := z2 xor z3 xor z5 xor z7 xor z8;
        r7 := z3 xor z4 xor z5 xor z6 xor z8;
        r8 := z1 xor z4 xor z5 xor z6 xor z7;
        
        return r1 & r2 & r3 & r4 & r5 & r6 & r7 & r8;

    end function camellia_f;

    function camellia_fl(x: camellia_w64_t; kl: camellia_w64_t) return camellia_w64_t is
        variable y: camellia_w64_t;
    begin
        y(32 to 63) := x(32 to 63) xor rotate_left32(x(0 to 31) and kl(0 to 31));
        y(0 to 31) := x(0 to 31) xor (y(32 to 63) or kl(32 to 63));

        return y;

    end function camellia_fl;

    function camellia_fl_inv(y: camellia_w64_t; kl: camellia_w64_t) return camellia_w64_t is
        variable x: camellia_w64_t;
    begin
        x(0 to 31) := y(0 to 31) xor (y(32 to 63) or kl(32 to 63));
        x(32 to 63) := y(32 to 63) xor rotate_left32(x(0 to 31) and kl(0 to 31));

        return x;

    end function camellia_fl_inv;

    -- Camellia 128

    function camellia_key_sched(k: camellia_w128_t) return camellia_w128_t is
    constant sigma1: camellia_w64_t := x"A09E667F3BCC908B";
    constant sigma2: camellia_w64_t := x"B67AE8584CAA73B2";
    constant sigma3: camellia_w64_t := x"C6EF372FE94F82BE";
    constant sigma4: camellia_w64_t := x"54FF53A5F1D36F1C";

    variable KL, KA: camellia_w128_t;
    variable t0, t1: camellia_w64_t;
    begin
        KL := k;

        t0 := KL(0  to 63);
        t1 := KL(64 to 127);

        t1 := t1 xor camellia_f(t0, sigma1);
        t0 := t0 xor camellia_f(t1, sigma2);

        t0 := t0 xor KL(0  to 63);
        t1 := t1 xor KL(64 to 127);

        t1 := t1 xor camellia_f(t0, sigma3);
        t0 := t0 xor camellia_f(t1, sigma4);

        KA := t0 & t1; 

        -- No need for KB with 128 bits key

        return KA;

    end function camellia_key_sched;

    function camellia_6rounds(r: camellia_w64_t; l: camellia_w64_t; k1, k2, k3, k4, k5, k6: camellia_w64_t) return camellia_w128_t is
    variable t0, t1, tmp: camellia_w64_t;
    begin
        t0 := r xor camellia_f(l, k1);
        t1 := l;
        tmp := t0;
        t0 := t1 xor camellia_f(t0, k2);
        t1 := tmp;
        tmp := t0;
        t0 := t1 xor camellia_f(t0, k3);
        t1 := tmp;
        tmp := t0;
        t0 := t1 xor camellia_f(t0, k4);
        t1 := tmp;
        tmp := t0;
        t0 := t1 xor camellia_f(t0, k5);
        t1 := tmp;
        tmp := t0;
        t0 := t1 xor camellia_f(t0, k6);
        t1 := tmp;

        return t0 & t1;

    end function camellia_6rounds;

    function encr_camellia128(M, K: camellia_w128_t) return camellia_w128_t is
    variable KA: camellia_w128_t;
    variable kw1, kw2, kw3, kw4: camellia_w64_t;
    variable k1,  k2,  k3,  k4,  k5,  k6, k7,  k8,  k9,  k10, k11, k12, k13, k14, k15, k16, k17, k18: camellia_w64_t;
    variable kl1, kl2, kl3, kl4: camellia_w64_t; 
    variable L, R: camellia_w64_t;
    variable tmp: camellia_w128_t;

    begin
        -- Key initialization

        KA := camellia_key_sched(K);

        kw1 := K(0  to 63); 
        kw2 := K(64 to 127);
        kw3 := rotate_left128(KA, 111)(0  to 63);
        kw4 := rotate_left128(KA, 111)(64 to 127);

        k1 := KA(0  to 63);
        k2 := KA(64 to 127);
        k3 := rotate_left128(K, 15)(0  to 63);
        k4 := rotate_left128(K, 15)(64 to 127);
        k5 := rotate_left128(KA, 15)(0  to 63);
        k6 := rotate_left128(KA, 15)(64 to 127);
        k7  := rotate_left128(K, 45)(0  to 63);
        k8  := rotate_left128(K, 45)(64 to 127);
        k9  := rotate_left128(KA, 45)(0  to 63);
        k10 := rotate_left128(K, 60)(64 to 127);
        k11 := rotate_left128(KA, 60)(0  to 63);
        k12 := rotate_left128(KA, 60)(64 to 127);
        k13 := rotate_left128(K, 94)(0  to 63);
        k14 := rotate_left128(K, 94)(64 to 127);
        k15 := rotate_left128(KA, 94)(0  to 63);
        k16 := rotate_left128(KA, 94)(64 to 127);
        k17 := rotate_left128(K, 111)(0  to 63);
        k18 := rotate_left128(K, 111)(64 to 127);

        kl1 := rotate_left128(KA, 30)(0  to 63);
        kl2 := rotate_left128(KA, 30)(64 to 127);
        kl3 := rotate_left128(K, 77)(0  to 63);
        kl4 := rotate_left128(K, 77)(64 to 127);

        -- Algorithm

        L := M(0 to 63) xor kw1;
        R := M(64 to 127) xor kw2;

        tmp := camellia_6rounds(R, L, k1, k2, k3, k4, k5, k6);
        L := camellia_fl(tmp(0 to 63), kl1);
        R := camellia_fl_inv(tmp(64 to 127), kl2);

        tmp := camellia_6rounds(R, L, k7, k8, k9, k10, k11, k12);
        L := camellia_fl(tmp(0 to 63), kl3);
        R := camellia_fl_inv(tmp(64 to 127), kl4);
        
        tmp := camellia_6rounds(R, L, k13, k14, k15, k16, k17, k18);
        L := tmp(64 to 127) xor kw3;
        R := tmp(0 to 63) xor kw4; 

        return L & R;

    end function encr_camellia128;

    ------------------------------------------------------------------------------------
    -- Completion function for A and C last block

    function complete(data: std_logic_vector(127 downto 0); bytes: std_logic_vector(3 downto 0); is_last: std_logic) return std_logic_vector is
        variable res: std_logic_vector(127 downto 0);
        variable n: integer;
    begin
        res := data;
        if is_last = '1' then
            if bytes = "0000" then
                n := 16;
            else
                n := to_integer(unsigned(bytes));
            end if ;
            
            for i in 0 to 15 loop
                if i >= n then
                    res(127 - (i*8) downto 120 - (i*8)) := x"00";
                end if;
            end loop;
        end if ;
        return res;

    end function complete;

end package body gcm_pkg;
