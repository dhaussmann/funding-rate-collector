// Quick test für Paradex Collector
import { collectCurrentParadex } from './src/collectors/paradex';

// Mock Env (ohne echte DB)
const mockEnv = {
  DB: null as any,
};

async function testParadexCollector() {
  console.log('🧪 Testing Paradex Collector...\n');

  try {
    const result = await collectCurrentParadex(mockEnv);

    console.log('✅ Collection erfolgreich!');
    console.log(`📊 Gefunden: ${result.unified.length} Markets\n`);

    // Zeige Top 10 nach absoluter Funding Rate sortiert
    const sorted = result.unified.sort((a, b) =>
      Math.abs(b.fundingRate) - Math.abs(a.fundingRate)
    );

    console.log('Top 10 Markets (nach höchster absoluter Funding Rate):');
    console.log('─'.repeat(80));
    sorted.slice(0, 10).forEach((rate, i) => {
      console.log(
        `${(i + 1).toString().padStart(2)}. ${rate.tradingPair.padEnd(20)} | ` +
        `Rate: ${(rate.fundingRatePercent).toFixed(4).padStart(8)}% | ` +
        `Annualized: ${(rate.annualizedRate).toFixed(2).padStart(8)}%`
      );
    });

    console.log('\n📈 Statistiken:');
    console.log(`   Positive Rates: ${result.unified.filter(r => r.fundingRate > 0).length}`);
    console.log(`   Negative Rates: ${result.unified.filter(r => r.fundingRate < 0).length}`);
    console.log(`   Durchschnitt:   ${(result.unified.reduce((sum, r) => sum + r.fundingRatePercent, 0) / result.unified.length).toFixed(4)}%`);

  } catch (error) {
    console.error('❌ Fehler:', error);
    process.exit(1);
  }
}

testParadexCollector();
