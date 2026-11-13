import Ledger
import Testing

@Test func aEuroAmountParsesToIntegerCents() {
    #expect(Cents(euroText: "12.50") == Cents(1250))
    #expect(Cents(euroText: "19,99") == Cents(1999))
    #expect(Cents(euroText: "12") == Cents(1200))
    #expect(Cents(euroText: "0.01") == Cents(1))
    #expect(Cents(euroText: "12.5") == Cents(1250))
    #expect(Cents(euroText: "") == nil)
    #expect(Cents(euroText: "12.555") == nil)
    #expect(Cents(euroText: "-1.00") == nil)
}
