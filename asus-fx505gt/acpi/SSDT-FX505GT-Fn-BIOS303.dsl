// SPDX-License-Identifier: MIT
// FX505GT BIOS303 source candidate. Exact matching DSDT rename required.
// Never install without native ACPI compiler/review and hardware authorization.
DefinitionBlock ("", "SSDT", 2, "FX505G", "FN303", 0x00000001)
{
    External (\_SB.PCI0.LPCB.EC0, DeviceObj)
    External (\_SB.ATKD, DeviceObj)
    External (\_SB.ATKD.IANE, MethodObj)
    External (\SLKI, MethodObj)
    External (\_SB.PCI0.LPCB.EC0.XQ0A, MethodObj)
    External (\_SB.PCI0.LPCB.EC0.XQ0B, MethodObj)
    External (\_SB.PCI0.LPCB.EC0.XQ0C, MethodObj)
    External (\_SB.PCI0.LPCB.EC0.XQ0D, MethodObj)
    External (\_SB.PCI0.LPCB.EC0.XQ0E, MethodObj)
    External (\_SB.PCI0.LPCB.EC0.XQ0F, MethodObj)
    External (\_SB.PCI0.LPCB.EC0.XQ10, MethodObj)
    External (\_SB.PCI0.LPCB.EC0.XQ11, MethodObj)
    External (\_SB.PCI0.LPCB.EC0.XQ12, MethodObj)
    External (\_SB.PCI0.LPCB.EC0.XQ13, MethodObj)
    External (\_SB.PCI0.LPCB.EC0.XQ14, MethodObj)
    External (\_SB.PCI0.LPCB.EC0.XQ15, MethodObj)
    External (\_SB.PCI0.LPCB.EC0.XQ6B, MethodObj)
    External (\_SB.PCI0.LPCB.EC0.XQ6C, MethodObj)
    Scope (\_SB.PCI0.LPCB.EC0)
    {
        // Explicit source opt-in, off even if this candidate is compiled.
        Name (FXEN, Zero)
        // Fn+F1; source-derived _Q correlation, physical test pending.
        Method (_Q0A, 0, NotSerialized)
        {
            If (LAnd (_OSI ("Darwin"), FXEN))
            {
                \_SB.ATKD.IANE (0xF501)
            }
            Else
            {
                XQ0A ()
            }
        }
        // Fn+F2; source-derived _Q correlation, physical test pending.
        Method (_Q0B, 0, NotSerialized)
        {
            If (LAnd (_OSI ("Darwin"), FXEN))
            {
                \_SB.ATKD.IANE (0xF502)
            }
            Else
            {
                XQ0B ()
            }
        }
        // Fn+F3; source-derived _Q correlation, physical test pending.
        Method (_Q0C, 0, NotSerialized)
        {
            If (LAnd (_OSI ("Darwin"), FXEN))
            {
                \_SB.ATKD.IANE (0xF503)
            }
            Else
            {
                XQ0C ()
            }
        }
        // Fn+F4; source-derived _Q correlation, physical test pending.
        Method (_Q0D, 0, NotSerialized)
        {
            If (LAnd (_OSI ("Darwin"), FXEN))
            {
                \_SB.ATKD.IANE (0xF504)
            }
            Else
            {
                XQ0D ()
            }
        }
        // Fn+F5; source-derived _Q correlation, physical test pending.
        Method (_Q0E, 0, NotSerialized)
        {
            If (LAnd (_OSI ("Darwin"), FXEN))
            {
                \_SB.ATKD.IANE (0xF505)
            }
            Else
            {
                XQ0E ()
            }
        }
        // Fn+F6; source-derived _Q correlation, physical test pending.
        Method (_Q0F, 0, NotSerialized)
        {
            If (LAnd (_OSI ("Darwin"), FXEN))
            {
                \_SB.ATKD.IANE (0xF506)
            }
            Else
            {
                XQ0F ()
            }
        }
        // Fn+F7; source-derived _Q correlation, physical test pending.
        Method (_Q10, 0, NotSerialized)
        {
            If (LAnd (_OSI ("Darwin"), FXEN))
            {
                \_SB.ATKD.IANE (0xF507)
            }
            Else
            {
                XQ10 ()
            }
        }
        // Fn+F8; source-derived _Q correlation, physical test pending.
        Method (_Q11, 0, NotSerialized)
        {
            If (LAnd (_OSI ("Darwin"), FXEN))
            {
                \_SB.ATKD.IANE (0xF508)
            }
            Else
            {
                XQ11 ()
            }
        }
        // Fn+F9; source-derived _Q correlation, physical test pending.
        Method (_Q12, 0, NotSerialized)
        {
            If (LAnd (_OSI ("Darwin"), FXEN))
            {
                \_SB.ATKD.IANE (0xF509)
            }
            Else
            {
                XQ12 ()
            }
        }
        // Fn+F10; source-derived _Q correlation, physical test pending.
        Method (_Q13, 0, NotSerialized)
        {
            If (LAnd (_OSI ("Darwin"), FXEN))
            {
                \_SB.ATKD.IANE (0xF50A)
            }
            Else
            {
                XQ13 ()
            }
        }
        // Fn+F11; source-derived _Q correlation, physical test pending.
        Method (_Q14, 0, NotSerialized)
        {
            If (LAnd (_OSI ("Darwin"), FXEN))
            {
                \_SB.ATKD.IANE (0xF50B)
            }
            Else
            {
                XQ14 ()
            }
        }
        // Fn+F12; source-derived _Q correlation, physical test pending.
        Method (_Q15, 0, NotSerialized)
        {
            If (LAnd (_OSI ("Darwin"), FXEN))
            {
                \_SB.ATKD.IANE (0xF50C)
            }
            Else
            {
                XQ15 ()
            }
        }
        // Fn+Up; source-derived _Q correlation, physical test pending.
        Method (_Q6B, 0, NotSerialized)
        {
            If (LAnd (_OSI ("Darwin"), FXEN))
            {
                \_SB.ATKD.IANE (0xF50D)
            }
            Else
            {
                XQ6B ()
            }
        }
        // Fn+Down; source-derived _Q correlation, physical test pending.
        Method (_Q6C, 0, NotSerialized)
        {
            If (LAnd (_OSI ("Darwin"), FXEN))
            {
                \_SB.ATKD.IANE (0xF50E)
            }
            Else
            {
                XQ6C ()
            }
        }
    }
    Scope (\_SB.ATKD)
    {
        // Stock AsusSMC supplies a 0..255 level. No arbitrary EC access.
        Method (SKBV, 1, Serialized)
        {
            If (LNot (LAnd (_OSI ("Darwin"), \_SB.PCI0.LPCB.EC0.FXEN)))
            {
                Return (Zero)
            }
            If (LNotEqual (ObjectType (Arg0), One)) { Return (Zero) }
            If (LGreater (Arg0, 0xFF)) { Return (Zero) }
            ShiftRight (Arg0, 0x04, Local0)
            Or (Local0, 0x80, Local0)
            Return (\SLKI (Local0))
        }
    }
}
