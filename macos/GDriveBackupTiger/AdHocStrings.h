#import <Foundation/Foundation.h>

static inline NSString *GDTAdHocText(NSString *language, NSString *key) {
    NSDictionary *strings = @{
        @"automatic": @[@"Automatisches Ziel", @"Automatic destination"],
        @"storage": @[@"Speicher am automatischen Ziel", @"Automatic destination space"],
        @"choose": @[@"Dieses Backup sichern auf:", @"Save this backup to:"],
        @"once": @[@"Nur für diesen Lauf. Der automatische Zeitplan bleibt unverändert.", @"For this run only. The automatic schedule stays unchanged."],
        @"missing": @[@"nicht angeschlossen", @"not connected"],
        @"unsafe": @[@"Ziel nicht eindeutig oder nicht beschreibbar", @"Destination ambiguous or not writable"],
        @"add": @[@"Anderes Backup-Ziel hinzufügen …", @"Add another backup destination …"],
        @"adding": @[@"Externe Festplatte hinzufügen", @"Add external disk"],
        @"addDetail": @[@"Wähle ein vorhandenes APFS-Volume. Es wird als zusätzliches manuelles Ziel gespeichert. Vorhandene Daten bleiben erhalten. Es wird nichts formatiert.", @"Choose an existing APFS volume. It will be saved as an additional manual destination. Existing data is kept. Nothing is formatted."],
        @"save": @[@"Als manuelles Ziel hinzufügen", @"Add as manual destination"],
        @"checking": @[@"Ziel wird geprüft …", @"Checking destination …"],
        @"unavailable": @[@"Das gewählte Ziel ist nicht mehr eindeutig verfügbar. Bitte erneut anschließen oder ein anderes Ziel wählen.", @"The selected destination is no longer uniquely available. Reconnect it or choose another destination."],
        @"on": @[@"Backup auf %@", @"Backup to %@"],
        @"none": @[@"Keine geeignete externe APFS-Festplatte angeschlossen.", @"No suitable external APFS disk connected."],
        @"volume": @[@"Volume", @"Volume"]
        ,@"engine": @[@"Bitte die aktuelle App vollständig installieren. Die installierte Backup-Routine unterstützt die einmalige Zielwahl noch nicht.", @"Please install the complete current app. The installed backup engine does not yet support one-run destination selection."]
    };
    NSArray *values = strings[key];
    return values ? values[[language isEqualToString:@"de"] ? 0 : 1] : key;
}
