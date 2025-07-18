//
//  SPDatabaseDocument.m
//  sequel-pro
//
//  Created by Lorenz Textor (lorenz@textor.ch) on May 1, 2002.
//  Copyright (c) 2002-2003 Lorenz Textor. All rights reserved.
//  Copyright (c) 2012 Sequel Pro Team. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  More info at <https://github.com/sequelpro/sequelpro>

#import "SPDatabaseDocument.h"
#import "SPConnectionController.h"
#import "SPTablesList.h"
#import "SPDatabaseStructure.h"
#import "SPFileHandle.h"
#import "SPKeychain.h"
#import "SPTableContent.h"
#import "SPCustomQuery.h"
#import "SPDataImport.h"
#import "ImageAndTextCell.h"
#import "SPExportController.h"
#import "SPSplitView.h"
#import "SPQueryController.h"
#import "SPNavigatorController.h"
#import "SPSQLParser.h"
#import "SPTableData.h"
#import "SPDatabaseData.h"
#import "SPExtendedTableInfo.h"
#import "SPHistoryController.h"
#import "SPPreferenceController.h"
#import "SPUserManager.h"
#import "SPEncodingPopupAccessory.h"
#import "YRKSpinningProgressIndicator.h"
#import "SPProcessListController.h"
#import "SPServerVariablesController.h"
#import "SPLogger.h"
#import "SPDatabaseCopy.h"
#import "SPTableCopy.h"
#import "SPDatabaseRename.h"
#import "SPTableRelations.h"
#import "SPCopyTable.h"
#import "SPServerSupport.h"
#import "SPTooltip.h"
#import "SPThreadAdditions.h"
#import "RegexKitLite.h"
#import "SPTextView.h"
#import "SPFavoriteColorSupport.h"
#import "SPCharsetCollationHelper.h"
#import "SPGotoDatabaseController.h"
#import "SPFunctions.h"
#import "SPCreateDatabaseInfo.h"
#import "SPAppController.h"
#import "SPBundleHTMLOutputController.h"
#import "SPTableTriggers.h"
#import "SPTableStructure.h"
#import "SPPrintAccessory.h"
#import "MGTemplateEngine.h"
#import "ICUTemplateMatcher.h"
#import "SPFavoritesOutlineView.h"
#import "SPSSHTunnel.h"
#import "SPHelpViewerClient.h"
#import "SPHelpViewerController.h"
#import "SPPrintUtility.h"
#import "SPBundleManager.h"

#import "sequel-ace-Swift.h"

#import <SPMySQL/SPMySQL.h>

#include <stdatomic.h>

// Constants
static NSString *SPNewDatabaseDetails = @"SPNewDatabaseDetails";
static NSString *SPNewDatabaseName = @"SPNewDatabaseName";
static NSString *SPNewDatabaseCopyContent = @"SPNewDatabaseCopyContent";

static _Atomic int SPDatabaseDocumentInstanceCounter = 0;

@interface SPDatabaseDocument ()

// Privately redeclare as read/write to get the synthesized setter
@property (readwrite, assign) BOOL allowSplitViewResizing;

// images
@property (nonatomic, strong) NSImage *hideConsoleImage;
@property (nonatomic, strong) NSImage *showConsoleImage;
@property (nonatomic, strong) NSImage *textAndCommandMacwindowImage API_AVAILABLE(macos(11.0));
@property (nonatomic, weak, readwrite) SPWindowController *parentWindowController;
@property (assign) BOOL appIsTerminating;

@property (readwrite, nonatomic, strong) NSToolbar *mainToolbar;

- (void)_addDatabase;
- (void)_alterDatabase;
- (void)_copyDatabase;
- (void)_renameDatabase;
- (void)_removeDatabase;
- (void)_selectDatabaseAndItem:(NSDictionary *)selectionDetails;
- (void)_processDatabaseChangedBundleTriggerActions;
- (void)_addPreferenceObservers;
- (void)_removePreferenceObservers;

#pragma mark - SPDatabaseViewControllerPrivateAPI

- (void)_loadTabTask:(NSNumber *)tabViewItemIndexNumber;
- (void)_loadTableTask;

#pragma mark - SPConnectionDelegate

- (void) closeAndDisconnect;

- (NSString *)keychainPasswordForConnection:(SPMySQLConnection *)connection;
- (NSString *)keychainPasswordForSSHConnection:(SPMySQLConnection *)connection;

@end

@implementation SPDatabaseDocument

@synthesize sqlFileURL;
@synthesize sqlFileEncoding;
@synthesize isProcessing;
@synthesize serverSupport;
@synthesize databaseStructureRetrieval;
@synthesize processID;
@synthesize instanceId;
@synthesize dbTablesTableView;
@synthesize tableDumpInstance;
@synthesize tablesListInstance;
@synthesize tableContentInstance;
@synthesize customQueryInstance;
@synthesize allowSplitViewResizing;
@synthesize hideConsoleImage;
@synthesize showConsoleImage;
@synthesize textAndCommandMacwindowImage;
@synthesize appIsTerminating;
@synthesize multipleLineEditingButton;

#pragma mark -

+ (void)initialize {
}

- (instancetype)initWithWindowController:(SPWindowController *)windowController {
    if (self = [super init]) {
        _parentWindowController = windowController;

        instanceId = atomic_fetch_add(&SPDatabaseDocumentInstanceCounter, 1);

        _mainNibLoaded = NO;
        _isConnected = NO;
        _isWorkingLevel = 0;
        _isSavedInBundle = NO;
        _supportsEncoding = NO;
        databaseListIsSelectable = YES;
        _queryMode = SPInterfaceQueryMode;

        initComplete = NO;
        allowSplitViewResizing = NO;

        chooseDatabaseButton = nil;
        chooseDatabaseToolbarItem = nil;
        connectionController = nil;

        selectedTableName = nil;
        selectedTableType = SPTableTypeNone;

        structureLoaded = NO;
        contentLoaded = NO;
        statusLoaded = NO;
        triggersLoaded = NO;
        relationsLoaded = NO;
        appIsTerminating = NO;

        hideConsoleImage = [NSImage imageNamed:@"hideconsole"];
        showConsoleImage = [NSImage imageNamed:@"showconsole"];
        if (@available(macOS 11.0, *)) {
            textAndCommandMacwindowImage = [NSImage imageWithSystemSymbolName:@"text.and.command.macwindow" accessibilityDescription:nil];
        }

        selectedDatabase = nil;
        selectedDatabaseEncoding = @"latin1";
        mySQLConnection = nil;
        mySQLVersion = nil;
        allDatabases = nil;
        allSystemDatabases = nil;
        gotoDatabaseController = nil;

        isProcessing = NO;

        printWebView = [[WebView alloc] init];
        [printWebView setFrameLoadDelegate:self];

        prefs = [NSUserDefaults standardUserDefaults];
        undoManager = [[NSUndoManager alloc] init];
        queryEditorInitString = nil;

        sqlFileURL = nil;
        spfFileURL = nil;
        spfSession = nil;
        spfPreferences = [[NSMutableDictionary alloc] init];
        spfDocData = [[NSMutableDictionary alloc] init];
        runningActivitiesArray = [[NSMutableArray alloc] init];

        taskProgressWindow = nil;
        taskDisplayIsIndeterminate = YES;
        taskDisplayLastValue = 0;
        taskProgressValue = 0;
        taskProgressValueDisplayInterval = 1;
        taskDrawTimer = nil;
        taskFadeInStartDate = nil;
        taskCanBeCancelled = NO;
        taskCancellationCallbackObject = nil;
        taskCancellationCallbackSelector = NULL;
        alterDatabaseCharsetHelper = nil; //init in awakeFromNib
        addDatabaseCharsetHelper = nil;

        statusValues = nil;
        printThread = nil;
        windowTitleStatusViewIsVisible = NO;

        // As this object is not an NSWindowController subclass, top-level objects in loaded nibs aren't
        // automatically released.  Keep track of the top-level objects for release on dealloc.
        NSArray *dbViewTopLevelObjects = nil;
        NSNib *nibLoader = [[NSNib alloc] initWithNibNamed:@"DBView" bundle:[NSBundle mainBundle]];
        [nibLoader instantiateWithOwner:self topLevelObjects:&dbViewTopLevelObjects];

        databaseStructureRetrieval = [[SPDatabaseStructure alloc] initWithDelegate:self];
    }

    return self;
}

- (void)awakeFromNib
{
    if (_mainNibLoaded) return;
    [super awakeFromNib];

    _mainNibLoaded = YES;

    // Update the toolbar
    [self.parentWindowControllerWindow setToolbar:self.mainToolbar];

    // The history controller needs to track toolbar item state - trigger setup.
    [spHistoryControllerInstance setupInterface];

    // Set collapsible behaviour on the table list so collapsing behaviour handles resize issus
    [contentViewSplitter setCollapsibleSubviewIndex:0];

    // Set a minimum size on both text views on the table info page
    [tableInfoSplitView setMinSize:20 ofSubviewAtIndex:0];
    [tableInfoSplitView setMinSize:20 ofSubviewAtIndex:1];

    // Set up the connection controller
    connectionController = [[SPConnectionController alloc] initWithDocument:self];

    // Set the connection controller's delegate
    [connectionController setDelegate:self];

    // Register preference observers to allow live UI-linked preference changes
    [self _addPreferenceObservers];

    // Register for notifications
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(willPerformQuery:)
               name:@"SMySQLQueryWillBePerformed"
             object:self];

    [nc addObserver:self
           selector:@selector(hasPerformedQuery:)
               name:@"SMySQLQueryHasBeenPerformed"
             object:self];

    [nc addObserver:self
           selector:@selector(applicationWillTerminate:)
               name:@"NSApplicationWillTerminateNotification"
             object:nil];

    [nc addObserver:self selector:@selector(documentWillClose:) name:SPDocumentWillCloseNotification object:nil];

    // Find the Database -> Database Encoding menu (it's not in our nib, so we can't use interface builder)
    selectEncodingMenu = [[[[[NSApp mainMenu] itemWithTag:SPMainMenuDatabase] submenu] itemWithTag:1] submenu];

    // Hide the tabs in the tab view (we only show them to allow switching tabs in interface builder)
    [tableTabView setTabViewType:NSNoTabsNoBorder];

    // Hide the activity list
    [self setActivityPaneHidden:@1];

    // Load additional nibs, keeping track of the top-level objects to allow correct release
    NSArray *connectionDialogTopLevelObjects = nil;
    NSNib *nibLoader = [[NSNib alloc] initWithNibNamed:@"ConnectionErrorDialog" bundle:[NSBundle mainBundle]];
    [nibLoader instantiateWithOwner:self topLevelObjects:&connectionDialogTopLevelObjects];

    NSArray *progressIndicatorLayerTopLevelObjects = nil;
    nibLoader = [[NSNib alloc] initWithNibNamed:@"ProgressIndicatorLayer" bundle:[NSBundle mainBundle]];
    [nibLoader instantiateWithOwner:self topLevelObjects:&progressIndicatorLayerTopLevelObjects];

    // Set up the progress indicator child window and layer - change indicator color and size
    [taskProgressIndicator setForeColor:[NSColor whiteColor]];
    NSShadow *progressIndicatorShadow = [[NSShadow alloc] init];
    [progressIndicatorShadow setShadowOffset:NSMakeSize(1.0f, -1.0f)];
    [progressIndicatorShadow setShadowBlurRadius:1.0f];
    [progressIndicatorShadow setShadowColor:[NSColor colorWithCalibratedWhite:0.0f alpha:0.75f]];
    [taskProgressIndicator setShadow:progressIndicatorShadow];
    taskProgressWindow = [[NSWindow alloc] initWithContentRect:[taskProgressLayer bounds] styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    [taskProgressWindow setReleasedWhenClosed:NO];
    [taskProgressWindow setOpaque:NO];
    [taskProgressWindow setBackgroundColor:[NSColor clearColor]];
    [taskProgressWindow setAlphaValue:0.0f];
    [taskProgressWindow setContentView:taskProgressLayer];

    alterDatabaseCharsetHelper = [[SPCharsetCollationHelper alloc] initWithCharsetButton:databaseAlterEncodingButton CollationButton:databaseAlterCollationButton];
    addDatabaseCharsetHelper   = [[SPCharsetCollationHelper alloc] initWithCharsetButton:databaseEncodingButton CollationButton:databaseCollationButton];

    // Update the window's title and represented document
    [self updateWindowTitle:self];
    [self.parentWindowControllerWindow setRepresentedURL:(spfFileURL && [spfFileURL isFileURL] ? spfFileURL : nil)];

    // Add the progress window to this window
    [self centerTaskWindow];

    // If not connected, update the favorite selection
    if (!_isConnected) {
        [connectionController updateFavoriteNextKeyView];
    }

    initComplete = YES;
}

#pragma mark - Accessors

- (NSToolbar *)mainToolbar {
    if (!_mainToolbar) {
        _mainToolbar = [[NSToolbar alloc] initWithIdentifier:@"TableWindowToolbar"];
        [_mainToolbar setAllowsUserCustomization:YES];
        [_mainToolbar setAutosavesConfiguration:YES];
        [_mainToolbar setDelegate:self];
    }
    return _mainToolbar;
}

#pragma mark -

/**
 * Set the return code for entering the encryption passowrd sheet
 */
- (IBAction)closePasswordSheet:(id)sender {
    passwordSheetReturnCode = 0;
    if ([sender tag]) {
        [NSApp stopModal];
        passwordSheetReturnCode = 1;
    }
    [NSApp abortModal];
}

/**
 * Go backward or forward in the history depending on the menu item selected.
 */
- (void)backForwardInHistory:(id)sender {
    // Ensure history navigation is permitted - trigger end editing and any required saves
    if (![self couldCommitCurrentViewActions]) {
        return;
    }

    switch ([sender tag]) {
        case 0: // Go backward
            [spHistoryControllerInstance goBackInHistory];
            break;
        case 1: // Go forward
            [spHistoryControllerInstance goForwardInHistory];
            break;
    }
}

#pragma mark -
#pragma mark Connection callback and methods

/**
 *
 * This method *MUST* be called from the UI thread!
 */
- (void)setConnection:(SPMySQLConnection *)theConnection
{
    if ([theConnection userTriggeredDisconnect]) {
        return;
    }

    _isConnected = YES;
    mySQLConnection = theConnection;

    // Now that we have a connection, determine what functionality the database supports.
    // Note that this must be done before anything else as it's used by nearly all of the main controllers.
    serverSupport = [[SPServerSupport alloc] initWithMajorVersion:[mySQLConnection serverMajorVersion]
                                                            minor:[mySQLConnection serverMinorVersion]
                                                          release:[mySQLConnection serverReleaseVersion]];

    // Set the fileURL and init the preferences (query favs, filters, and history) if available for that URL
    NSURL *newURL = [[SPQueryController sharedQueryController] registerDocumentWithFileURL:[self fileURL] andContextInfo:spfPreferences];
    [self setFileURL:newURL];

    // ...but hide the icon while the document is temporary
    if ([self isUntitled]) {
        [[[self.parentWindowController window] standardWindowButton:NSWindowDocumentIconButton] setImage:nil];
    }

    // Get the mysql version
    mySQLVersion = [mySQLConnection serverVersionString] ;

    NSString *tmpDb = [connectionController database];

    // Update the selected database if appropriate
    if (tmpDb != nil && ![tmpDb isEqualToString:@""]) {
        selectedDatabase = tmpDb;
        [spHistoryControllerInstance updateHistoryEntries];
    }

    // Ensure the connection encoding is set to utf8 for database/table name retrieval
    [mySQLConnection setEncoding:@"utf8mb4"];

    // Check if skip-show-database is set to ON
    if ( [prefs boolForKey:SPShowWarningSkipShowDatabase] ) {
        SPMySQLResult *result = [mySQLConnection queryString:@"SHOW VARIABLES LIKE 'skip_show_database'"];
        [result setReturnDataAsStrings:YES];
        if(![mySQLConnection queryErrored] && [result numberOfRows] == 1) {
            NSString *skip_show_database = [[result getRowAsDictionary] objectForKey:@"Value"];
            if ([skip_show_database.lowercaseString isEqualToString:@"on"]) {
                [NSAlert createAlertWithTitle:NSLocalizedString(@"Warning",@"warning")
                                      message:NSLocalizedString(@"The skip-show-database variable of the database server is set to ON. Thus, you won't be able to list databases unless you have the SHOW DATABASES privilege.\n\nHowever, the databases are still accessible directly through SQL queries depending on your privileges.", @"Warning message during connection in case the variable skip-show-database is set to ON")
                           primaryButtonTitle:NSLocalizedString(@"OK", @"OK button")
                         secondaryButtonTitle:NSLocalizedString(@"Never show this again", @"Never show this again")
                         primaryButtonHandler:^{ }
                       secondaryButtonHandler:^{ [self->prefs setBool:false forKey:SPShowWarningSkipShowDatabase]; }
                 ];
            }
        }
    }

    // Update the database list
    [self setDatabases];

    [chooseDatabaseButton setEnabled:!_isWorkingLevel];

    // Set the connection on the database structure builder
    [databaseStructureRetrieval setConnectionToClone:mySQLConnection];

    [databaseDataInstance setConnection:mySQLConnection];

    // Pass the support class to the data instance
    [databaseDataInstance setServerSupport:serverSupport];

    // Set the connection on the tables list instance - this updates the table list while the connection
    // is still UTF8
    [tablesListInstance setConnection:mySQLConnection];

    // Set the connection encoding if necessary
    NSNumber *encodingType = [prefs objectForKey:SPDefaultEncoding];

    if ([encodingType intValue] != SPEncodingAutodetect) {
        [self setConnectionEncoding:[self mysqlEncodingFromEncodingTag:encodingType] reloadingViews:NO];
    } else {
        [[self onMainThread] updateEncodingMenuWithSelectedEncoding:[self encodingTagFromMySQLEncoding:[mySQLConnection encoding]]];
    }

    // For each of the main controllers, assign the current connection
    SPLog(@"setConnection for each of main controllers");
    [tableSourceInstance setConnection:mySQLConnection];
    [tableContentInstance setConnection:mySQLConnection];
    [tableRelationsInstance setConnection:mySQLConnection];
    [tableTriggersInstance setConnection:mySQLConnection];
    [customQueryInstance setConnection:mySQLConnection];
    [tableDumpInstance setConnection:mySQLConnection];
    [exportControllerInstance setConnection:mySQLConnection];
    [exportControllerInstance setServerSupport:serverSupport];
    [tableDataInstance setConnection:mySQLConnection];
    [extendedTableInfoInstance setConnection:mySQLConnection];

    // Set the custom query editor's MySQL version
    [customQueryInstance setMySQLversion:mySQLVersion];

    [helpViewerClientInstance setConnection:mySQLConnection];

    [self updateWindowTitle:self];

    NSString *serverDisplayName = [[self.parentWindowController window] title];
    NSUserNotification *notification = [[NSUserNotification alloc] init];
    notification.title = @"Connected";
    notification.informativeText=[NSString stringWithFormat:NSLocalizedString(@"Connected to %@", @"description for connected notification"), serverDisplayName];
    notification.soundName = NSUserNotificationDefaultSoundName;

    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];

    // Init Custom Query editor with the stored queries in a spf file if given.
    [spfDocData setObject:@NO forKey:@"save_editor_content"];

    if (spfSession != nil && [spfSession objectForKey:@"queries"]) {
        [spfDocData setObject:@YES forKey:@"save_editor_content"];
        if ([[spfSession objectForKey:@"queries"] isKindOfClass:[NSData class]]) {
            NSString *q = [[NSString alloc] initWithData:[[spfSession objectForKey:@"queries"] decompress] encoding:NSUTF8StringEncoding];
            [self initQueryEditorWithString:q];
        }
        else {
            [self initQueryEditorWithString:[spfSession objectForKey:@"queries"]];
        }
    }

    // Insert queryEditorInitString into the Query Editor if defined
    if (queryEditorInitString && [queryEditorInitString length]) {
        [self viewQuery];
        [customQueryInstance doPerformLoadQueryService:queryEditorInitString];

    }

    if (spfSession != nil) {

        // Restore vertical split view divider for tables' list and right view (Structure, Content, etc.)
        if([spfSession objectForKey:@"windowVerticalDividerPosition"]) [contentViewSplitter setPosition:[[spfSession objectForKey:@"windowVerticalDividerPosition"] floatValue] ofDividerAtIndex:0];

        // Start a task to restore the session details
        [self startTaskWithDescription:NSLocalizedString(@"Restoring session...", @"Restoring session task description")];

        if ([NSThread isMainThread]) [NSThread detachNewThreadWithName:SPCtxt(@"SPDatabaseDocument session load task",self) target:self selector:@selector(restoreSession) object:nil];
        else                         [self restoreSession];
    }
    else {
        switch ([prefs integerForKey:SPDefaultViewMode] > 0 ? [prefs integerForKey:SPDefaultViewMode] : [prefs integerForKey:SPLastViewMode]) {
            default:
            case SPStructureViewMode:
                [self viewStructure];
                break;
            case SPContentViewMode:
                [self viewContent];
                break;
            case SPRelationsViewMode:
                [self viewRelations];
                break;
            case SPTableInfoViewMode:
                [self viewStatus];
                break;
            case SPQueryEditorViewMode:
                [self viewQuery];
                break;
            case SPTriggersViewMode:
                [self viewTriggers];
                break;
        }
    }

    if ([self database]) [self detectDatabaseEncoding];

    // If not on the query view, alter initial focus - set focus to table list filter
    // field if visible, otherwise set focus to Table List view
    if (![[self selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarCustomQuery]) {
        [[tablesListInstance onMainThread] makeTableListFilterHaveFocus];
    }

}

/**
 * Returns the current connection associated with this document.
 *
 * @return The document's connection
 */
- (SPMySQLConnection *)getConnection
{
    return mySQLConnection;
}

#pragma mark -
#pragma mark Database methods

/**
 * sets up the database select toolbar item
 *
 * This method *MUST* be called from the UI thread!
 */
- (void)setDatabases {
    if (!chooseDatabaseButton) {
        return;
    }

    [chooseDatabaseButton removeAllItems];

    [chooseDatabaseButton addItemWithTitle:NSLocalizedString(@"Choose Database...", @"menu item for choose db")];
    [[chooseDatabaseButton menu] addItem:[NSMenuItem separatorItem]];
    [[chooseDatabaseButton menu] addItemWithTitle:NSLocalizedString(@"Add Database...", @"menu item to add db") action:@selector(addDatabase:) keyEquivalent:@""];
    [[chooseDatabaseButton menu] addItemWithTitle:NSLocalizedString(@"Refresh Databases", @"menu item to refresh databases") action:@selector(setDatabases:) keyEquivalent:@""];
    [[chooseDatabaseButton menu] addItem:[NSMenuItem separatorItem]];


    NSArray *theDatabaseList = [mySQLConnection databases];

    allDatabases = [[NSMutableArray alloc] initWithCapacity:[theDatabaseList count]];
    allSystemDatabases = [[NSMutableArray alloc] initWithCapacity:2];

    for (NSString *databaseName in theDatabaseList)
    {
        // If the database is either information_schema or mysql then it is classed as a
        // system database; similarly, performance_schema in 5.5.3+ and sys in 5.7.7+
        if ([databaseName isEqualToString:SPMySQLDatabase] ||
            [databaseName isEqualToString:SPMySQLInformationSchemaDatabase] ||
            [databaseName isEqualToString:SPMySQLPerformanceSchemaDatabase] ||
            [databaseName isEqualToString:SPMySQLSysDatabase]) {
            [allSystemDatabases addObject:databaseName];
        }
        else {
            [allDatabases addObject:databaseName];
        }
    }

    // Add system databases
    for (NSString *database in allSystemDatabases)
    {
        [chooseDatabaseButton safeAddItemWithTitle:database];
    }

    // Add a separator between the system and user databases
    if ([allSystemDatabases count] > 0) {
        [[chooseDatabaseButton menu] addItem:[NSMenuItem separatorItem]];
    }

    // Add user databases
    for (NSString *database in allDatabases)
    {
        [chooseDatabaseButton safeAddItemWithTitle:database];
    }

    (![self database]) ? [chooseDatabaseButton selectItemAtIndex:0] : [chooseDatabaseButton selectItemWithTitle:[self database]];
}

/**
 * Selects the database choosen by the user, using a child task if necessary,
 * and displaying errors in an alert sheet on failure.
 */
- (IBAction)chooseDatabase:(id)sender
{
    if (![tablesListInstance selectionShouldChangeInTableView:nil]) {
        [chooseDatabaseButton selectItemWithTitle:[self database]];
        return;
    }

    if ( [chooseDatabaseButton indexOfSelectedItem] == 0 ) {
        if ([self database]) {
            [chooseDatabaseButton selectItemWithTitle:[self database]];
        }

        return;
    }

    // Lock editability again if performing a task
    if (_isWorkingLevel) databaseListIsSelectable = NO;

    // Select the database
    [self selectDatabase:[chooseDatabaseButton titleOfSelectedItem] item: nil];
}

/**
 * Select the specified database and, optionally, table.
 */
- (void)selectDatabase:(NSString *)database item:(NSString *)item
{
    // Do not update the navigator since nothing is changed
    [[SPNavigatorController sharedNavigatorController] setIgnoreUpdate:NO];

    // If Navigator runs in syncMode let it follow the selection
    if ([[[SPNavigatorController sharedNavigatorController] onMainThread] syncMode]) {
        NSMutableString *schemaPath = [NSMutableString string];

        [schemaPath setString:[self connectionID]];

        if([chooseDatabaseButton titleOfSelectedItem] && [[chooseDatabaseButton titleOfSelectedItem] length]) {
            [schemaPath appendString:SPUniqueSchemaDelimiter];
            [schemaPath appendString:[chooseDatabaseButton titleOfSelectedItem]];
        }

        [[SPNavigatorController sharedNavigatorController] selectPath:schemaPath];
    }

    // Start a task
    [self startTaskWithDescription:[NSString stringWithFormat:NSLocalizedString(@"Loading database '%@'...", @"Loading database task string"), database]];

    NSDictionary *selectionDetails = [NSDictionary dictionaryWithObjectsAndKeys:database, @"database", item, @"item", nil];

    if ([NSThread isMainThread]) {
        [NSThread detachNewThreadWithName:SPCtxt(@"SPDatabaseDocument database and table load task",self)
                                   target:self
                                 selector:@selector(_selectDatabaseAndItem:)
                                   object:selectionDetails];
    }
    else {
        [self _selectDatabaseAndItem:selectionDetails];
    }
}

/**
 * opens the add-db sheet and creates the new db
 */
- (void)addDatabase:(id)sender
{
    if (![tablesListInstance selectionShouldChangeInTableView:nil]) return;

    [databaseNameField setStringValue:@""];

    NSString *defaultCharset   = [databaseDataInstance getServerDefaultCharacterSet];
    NSString *defaultCollation = [databaseDataInstance getServerDefaultCollation];

    // Setup the charset and collation dropdowns
    [addDatabaseCharsetHelper setDatabaseData:databaseDataInstance];
    [addDatabaseCharsetHelper setDefaultCharsetFormatString:NSLocalizedString(@"Server Default (%@)", @"Add Database : Charset dropdown : default item ($1 = charset name)")];
    [addDatabaseCharsetHelper setDefaultCollationFormatString:NSLocalizedString(@"Server Default (%@)", @"Add Database : Collation dropdown : default item ($1 = collation name)")];
    [addDatabaseCharsetHelper setServerSupport:serverSupport];
    [addDatabaseCharsetHelper setPromoteUTF8:YES];
    [addDatabaseCharsetHelper setSelectedCharset:nil];
    [addDatabaseCharsetHelper setSelectedCollation:nil];
    [addDatabaseCharsetHelper setDefaultCharset:defaultCharset];
    [addDatabaseCharsetHelper setDefaultCollation:defaultCollation];
    [addDatabaseCharsetHelper setEnabled:YES];

    [[self.parentWindowController window] beginSheet:databaseSheet completionHandler:^(NSModalResponse returnCode) {
        [self->addDatabaseCharsetHelper setEnabled:NO];

        if (returnCode == NSModalResponseOK) {
            [self _addDatabase];

            // Query the structure of all databases in the background (mainly for completion)
            [self->databaseStructureRetrieval queryDbStructureInBackgroundWithUserInfo:@{@"forceUpdate" : @YES}];
        } else {
            // Reset chooseDatabaseButton
            if ([[self database] length]) {
                [self->chooseDatabaseButton selectItemWithTitle:[self database]];
            } else {
                [self->chooseDatabaseButton selectItemAtIndex:0];
            }
        }
    }];
}

/**
 * Show UI for the ALTER DATABASE statement
 */
- (void)alterDatabase {
    //once the database is created the charset and collation are written
    //to the db.opt file regardless if they were explicity given or not.
    //So there is no longer a "Default" option.

    NSString *currentCharset = [databaseDataInstance getDatabaseDefaultCharacterSet];
    NSString *currentCollation = [databaseDataInstance getDatabaseDefaultCollation];

    // Setup the charset and collation dropdowns
    [alterDatabaseCharsetHelper setDatabaseData:databaseDataInstance];
    [alterDatabaseCharsetHelper setServerSupport:serverSupport];
    [alterDatabaseCharsetHelper setPromoteUTF8:YES];
    [alterDatabaseCharsetHelper setSelectedCharset:currentCharset];
    [alterDatabaseCharsetHelper setSelectedCollation:currentCollation];
    [alterDatabaseCharsetHelper setEnabled:YES];

    [[self.parentWindowController window] beginSheet:databaseAlterSheet completionHandler:^(NSModalResponse returnCode) {

        [self->alterDatabaseCharsetHelper setEnabled:NO];
        if (returnCode == NSModalResponseOK) {
            [self _alterDatabase];
        }
    }];
}

- (IBAction)compareDatabase:(id)sender
{
    /*


     This method is a basic experiment to see how long it takes to read an string compare an entire database. It works,
     well, good performance and very little memory usage.

     Next we need to ask the user to select another connection (from the favourites list) and compare chunks of ~1000 rows
     at a time, ordered by primary key, between the two databases, using three threads (one for each database and one for
     comparisons).

     We will the write to disk every difference that has been found and open the result in FileMerge.

     In future, add the ability to write all difference to the current database.


     */
    NSLog(@"=================");

    SPMySQLResult *showTablesQuery = [mySQLConnection queryString:@"show tables"];

    NSArray *tableRow;
    while ((tableRow = [showTablesQuery getRowAsArray]) != nil) {
        @autoreleasepool {
            NSString *table = tableRow[0];

            NSLog(@"-----------------");
            NSLog(@"Scanning %@", table);


            NSDictionary *tableStatus = [[mySQLConnection queryString:[NSString stringWithFormat:@"SHOW TABLE STATUS LIKE %@", [table tickQuotedString]]] getRowAsDictionary];
            NSInteger rowCountEstimate = [tableStatus[@"Rows"] integerValue];
            NSLog(@"Estimated row count: %li", rowCountEstimate);



            SPMySQLResult *tableContentsQuery = [mySQLConnection streamingQueryString:[NSString stringWithFormat:@"select * from %@", [table backtickQuotedString]] useLowMemoryBlockingStreaming:NO];
            //NSDate *lastProgressUpdate = [NSDate date];
            time_t lastProgressUpdate = time(NULL);
            NSInteger rowCount = 0;
            NSArray *row;
            while (true) {
                @autoreleasepool {
                    row = [tableContentsQuery getRowAsArray];
                    if (!row) {
                        break;
                    }

                    [row isEqualToArray:row]; // TODO: compare to the other database, instead of the same one (just doing that to test performance)

                    rowCount++;
                    if ((time(NULL) - lastProgressUpdate) > 0) {
                        NSLog(@"Progress: %.1f%%", (((float)rowCount) / ((float)rowCountEstimate)) * 100);
                        lastProgressUpdate = time(NULL);
                    }
                }
            }
            NSLog(@"Done. Actual row count: %li", rowCount);
        }
    }

    NSLog(@"=================");
}

/**
 * Opens the copy database sheet and copies the databsae.
 */
- (void)copyDatabase {
    if (![tablesListInstance selectionShouldChangeInTableView:nil]) {
        return;
    }

    // Inform the user that we don't support copying objects other than tables and ask them if they'd like to proceed
    if ([tablesListInstance hasNonTableObjects]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:NSLocalizedString(@"Only Partially Supported", @"partial copy database support message")];
        [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Duplicating the database '%@' is only partially supported as it contains objects other than tables (i.e. views, procedures, functions, etc.), which will not be copied.\n\nWould you like to continue?", @"partial copy database support informative message"), selectedDatabase]];

        // Order of buttons matters! first button has "firstButtonReturn" return value from runModal()
        [alert addButtonWithTitle:NSLocalizedString(@"Continue", "continue button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"cancel button")];

        if ([alert runModal] == NSAlertSecondButtonReturn) {
            return;
        }
    }

    [databaseCopyNameField setStringValue:selectedDatabase];
    [copyDatabaseMessageField setStringValue:selectedDatabase];

    [[self.parentWindowController window] beginSheet:databaseCopySheet completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSModalResponseOK) {
            [self _copyDatabase];
        }
    }];
}

/**
 * Opens the rename database sheet and renames the databsae.
 */
- (void)renameDatabase {
    if (![tablesListInstance selectionShouldChangeInTableView:nil]) {
        return;
    }

    // We currently don't support moving any objects other than tables (i.e. views, functions, procs, etc.) from one database to another
    // so inform the user and don't allow them to proceed. Copy/duplicate is more appropriate in this case, but with the same limitation.
    if ([tablesListInstance hasNonTableObjects]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Database Rename Unsupported", @"databsse rename unsupported message") message:[NSString stringWithFormat:NSLocalizedString(@"Renaming the database '%@' is currently unsupported as it contains objects other than tables (i.e. views, procedures, functions, etc.).\n\nIf you would like to rename a database please use the 'Duplicate Database', move any non-table objects manually then drop the old database.", @"databsse rename unsupported informative message"), selectedDatabase] callback:nil];
        return;
    }

    [databaseRenameNameField setStringValue:selectedDatabase];
    [renameDatabaseMessageField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Rename database '%@' to:", @"rename database message"), selectedDatabase]];

    [[self.parentWindowController window] beginSheet:databaseRenameSheet completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSModalResponseOK) {
            [self _renameDatabase];
        }
    }];
}

/**
 * opens sheet to ask user if he really wants to delete the db
 */
- (void)removeDatabase:(id)sender {
    // No database selected, bail
    if ([chooseDatabaseButton indexOfSelectedItem] == 0) {
        return;
    }

    if (![tablesListInstance selectionShouldChangeInTableView:nil]) {
        return;
    }

    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"Delete database '%@'?", @"delete database message"), [self database]];
    NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to delete the database '%@'? This operation cannot be undone.", @"delete database informative message"), [self database]];
    [NSAlert createDefaultAlertWithTitle:title message:message primaryButtonTitle:NSLocalizedString(@"Delete", @"delete button") primaryButtonHandler:^{
        [self _removeDatabase];
    } cancelButtonHandler:nil];
}

/**
 * Refreshes the tables list by calling SPTablesList's updateTables.
 */
- (void)refreshTables {
    [tablesListInstance updateTables:self];
}

/**
 * Displays the database server variables sheet.
 */
- (void)showServerVariables {
    if (!serverVariablesController) {
        serverVariablesController = [[SPServerVariablesController alloc] init];

        [serverVariablesController setConnection:mySQLConnection];
    }

    [serverVariablesController displayServerVariablesSheetAttachedToWindow:[self.parentWindowController window]];
}

/**
 * Displays the database process list sheet.
 */
- (void)showServerProcesses {
    if (!processListController) {
        processListController = [[SPProcessListController alloc] init];

        [processListController setConnection:mySQLConnection];
    }

    [processListController displayProcessListWindow];
}

- (void)shutdownServer {
    [NSAlert createDefaultAlertWithTitle:NSLocalizedString(@"Do you really want to shutdown the server?", @"shutdown server : confirmation dialog : title") message:NSLocalizedString(@"This will wait for open transactions to complete and then quit the mysql daemon. Afterwards neither you nor anyone else can connect to this database!\n\nFull management access to the server's operating system is required to restart MySQL!", @"shutdown server : confirmation dialog : message") primaryButtonTitle:NSLocalizedString(@"Shutdown", @"shutdown server : confirmation dialog : shutdown button") primaryButtonHandler:^{
        if (![self->mySQLConnection serverShutdown]) {
            if ([self->mySQLConnection isConnected]) {
                [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Shutdown failed!", @"shutdown server : error dialog : title") message:[NSString stringWithFormat:NSLocalizedString(@"MySQL said:\n%@", @"shutdown server : error dialog : message"),[self->mySQLConnection lastErrorMessage]] callback:nil];
            }
        }
    } cancelButtonHandler:nil];
}

/**
 * Returns an array of all available database names
 */
- (NSArray *)allDatabaseNames
{
    return allDatabases;
}

/**
 * Returns an array of all available system database names
 */
- (NSArray *)allSystemDatabaseNames
{
    return allSystemDatabases;
}

/**
 * Show Error sheet (can be called from inside of a endSheet selector)
 * via [self performSelector:@selector(showErrorSheetWithTitle:) withObject: afterDelay:]
 */
-(void)showErrorSheetWith:(NSArray *)error {
    // error := first object is the title, second the message, only one button OK
    [NSAlert createWarningAlertWithTitle:[error objectAtIndex:0] message:[error objectAtIndex:1] callback:nil];
}

/**
 * Reset the current selected database name
 *
 * This method MAY be called from UI and background threads!
 */
- (void)refreshCurrentDatabase
{
    NSString *dbName = nil;

    // Notify listeners that a query has started
    [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:@"SMySQLQueryWillBePerformed" object:self];

    SPMySQLResult *theResult = [mySQLConnection queryString:@"SELECT DATABASE()"];
    [theResult setDefaultRowReturnType:SPMySQLResultRowAsArray];
    if (![mySQLConnection queryErrored]) {

        for (NSArray *eachRow in theResult)
        {
            dbName = [eachRow firstObject];
        }

        SPMainQSync(^{
            // TODO: there have been crash reports because dbName == nil at this point. When could that happen?
            if([dbName unboxNull]) {
                if([dbName respondsToSelector:@selector(isEqualToString:)]) {
                    if(![dbName isEqualToString:self->selectedDatabase]) {
                        self->selectedDatabase = [[NSString alloc] initWithString:dbName];
                        [self->chooseDatabaseButton selectItemWithTitle:self->selectedDatabase];
                        [self updateWindowTitle:self];
                    }
                }

            } else {

                [self->chooseDatabaseButton selectItemAtIndex:0];
                [self updateWindowTitle:self];
            }
        });
    }

    //query finished
    [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:@"SMySQLQueryHasBeenPerformed" object:self];
}

- (BOOL)navigatorSchemaPathExistsForDatabase:(NSString*)dbname
{
    return [[SPNavigatorController sharedNavigatorController] schemaPathExistsForConnection:[self connectionID] andDatabase:dbname];
}

- (NSDictionary*)getDbStructure
{
    return [[SPNavigatorController sharedNavigatorController] dbStructureForConnection:[self connectionID]];
}

- (NSArray *)allSchemaKeys
{
    return [[SPNavigatorController sharedNavigatorController] allSchemaKeysForConnection:[self connectionID]];
}

- (void)showGotoDatabase {
    if(!gotoDatabaseController) {
        gotoDatabaseController = [[SPGotoDatabaseController alloc] init];
    }

    NSMutableArray *dbList = [[NSMutableArray alloc] init];
    [dbList addObjectsFromArray:[self allSystemDatabaseNames]];
    [dbList addObjectsFromArray:[self allDatabaseNames]];
    [gotoDatabaseController setDatabaseList:dbList];

    if ([gotoDatabaseController runModal]) {
        NSString *database =[gotoDatabaseController selectedDatabase];
        if ([database rangeOfString:@"."].location != NSNotFound){
            NSArray *components = [database componentsSeparatedByString:@"."];
            [self selectDatabase:[components firstObject] item:[components lastObject]];
        }else{
            [self selectDatabase:database item:nil];
        }
    }
}

#pragma mark -
#pragma mark Console methods

/**
 * Shows or hides the console
 */
- (void)toggleConsole {
    // Toggle Console will show the Console window if it isn't visible or if it isn't
    // the front most window and hide it if it is the front most window
    if ([[[SPQueryController sharedQueryController] window] isVisible]
        && [[[NSApp keyWindow] windowController] isKindOfClass:[SPQueryController class]]) {

        [[[SPQueryController sharedQueryController] window] setIsVisible:NO];
    }
    else {
        [self showConsole];
    }
}

/**
 * Brings the console to the front
 */
- (void)showConsole {
    SPQueryController *queryController = [SPQueryController sharedQueryController];
    // If the Console window is not visible data are not reloaded (for speed).
    // Due to that update list if user opens the Console window.
    if (![[queryController window] isVisible]) {
        [queryController updateEntries];
    }

    [[queryController window] makeKeyAndOrderFront:self];
}

/**
 * Clears the console by removing all of its messages
 */
- (void)clearConsole:(id)sender {
    [[SPQueryController sharedQueryController] clearConsole:sender];
}

/**
 * Set a query mode, used to control logging dependant on preferences
 */
- (void) setQueryMode:(NSInteger)theQueryMode
{
    _queryMode = theQueryMode;
}

#pragma mark -
#pragma mark Navigator methods

/**
 * Shows or hides the navigator
 */
- (void)toggleNavigator {
    BOOL isNavigatorVisible = [[[SPNavigatorController sharedNavigatorController] window] isVisible];

    // Show or hide the navigator
    [[[SPNavigatorController sharedNavigatorController] window] setIsVisible:(!isNavigatorVisible)];

    if (!isNavigatorVisible) {
        [[SPNavigatorController sharedNavigatorController] updateEntriesForConnection:self];
    }
}

#pragma mark -
#pragma mark Task progress and notification methods

/**
 * Start a document-wide task, providing a short task description for
 * display to the user.  This sets the document into working mode,
 * preventing many actions, and shows an indeterminate progress interface
 * to the user.
 */
- (void) startTaskWithDescription:(NSString *)description
{
    SPLog(@"startTaskWithDescription: %@", description);

    // Ensure a call on the main thread
    if (![NSThread isMainThread]){
        SPLog(@"not on main thread, calling self again on main");
        return [[self onMainThread] startTaskWithDescription:description];
    }

    // Set the task text. If a nil string was supplied, a generic query notification is occurring -
    // if a task is not already active, use default text.
    if (!description) {
        if (!_isWorkingLevel) [self setTaskDescription:NSLocalizedString(@"Working...", @"Generic working description")];

        // Otherwise display the supplied string
    } else {
        [self setTaskDescription:description];
    }

    // Increment the task level
    _isWorkingLevel++;

    // Reset the progress indicator if necessary
    if (_isWorkingLevel == 1 || !taskDisplayIsIndeterminate) {
        taskDisplayIsIndeterminate = YES;
        [taskProgressIndicator setIndeterminate:YES];
        [taskProgressIndicator startAnimation:self];
        taskDisplayLastValue = 0;
    }

    // If the working level just moved to start a task, set up the interface
    if (_isWorkingLevel == 1) {
        [taskCancelButton setHidden:YES];

        // Set flags and prevent further UI interaction in this window
        databaseListIsSelectable = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:SPDocumentTaskStartNotification object:self];
        [self.mainToolbar validateVisibleItems];

        SPLog(@"Schedule appearance of the task window in the near future, using a frame timer");

        // Schedule appearance of the task window in the near future, using a frame timer.
        taskFadeInStartDate = [[NSDate alloc] init];
        queryStartDate = [[NSDate alloc] init];
        taskDrawTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0 target:self selector:@selector(fadeInTaskProgressWindow:) userInfo:nil repeats:YES];
        queryExecutionTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(showQueryExecutionTime) userInfo:nil repeats:YES];

    }
}

/**
 * Show query execution time on progress window.
 */
-(void)showQueryExecutionTime{

    double timeSinceQueryStarted = [[NSDate date] timeIntervalSinceDate:queryStartDate];

    NSString *queryRunningTime = [NSDateComponentsFormatter.hourMinSecFormatter stringFromTimeInterval:timeSinceQueryStarted];

    SPLog(@"showQueryExecutionTime: %@", queryRunningTime);

    NSShadow *textShadow = [[NSShadow alloc] init];
    [textShadow setShadowColor:[NSColor colorWithCalibratedWhite:0.0f alpha:0.75f]];
    [textShadow setShadowOffset:NSMakeSize(1.0f, -1.0f)];
    [textShadow setShadowBlurRadius:3.0f];

    NSMutableDictionary *attributes = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                       [NSFont boldSystemFontOfSize:13.0f], NSFontAttributeName,
                                       textShadow, NSShadowAttributeName,
                                       nil];
    NSAttributedString *queryRunningTimeString = [[NSAttributedString alloc] initWithString:queryRunningTime attributes:attributes];

    [taskDurationTime setAttributedStringValue:queryRunningTimeString];

}

/**
 * Show the task progress window, after a small delay to minimise flicker.
 */
- (void) fadeInTaskProgressWindow:(NSTimer *)theTimer
{
    SPLog(@"fadeInTaskProgressWindow");

    double timeSinceFadeInStart = [[NSDate date] timeIntervalSinceDate:taskFadeInStartDate];

    // Keep the window hidden for the first ~0.5 secs
    if (timeSinceFadeInStart < 0.5) return;

    if ([taskProgressWindow parentWindow] == nil) {
        [self.parentWindowControllerWindow addChildWindow:taskProgressWindow ordered:NSWindowAbove];
    }

    CGFloat alphaValue = [taskProgressWindow alphaValue];

    // If the task progress window is still hidden, center it before revealing it
    if (alphaValue == 0) [self centerTaskWindow];

    SPLog(@"Fade in the task window over 0.6 seconds");

    // Fade in the task window over 0.6 seconds
    alphaValue = (float)(timeSinceFadeInStart - 0.5) / 0.6f;
    if (alphaValue > 1.0f) alphaValue = 1.0f;
    [taskProgressWindow setAlphaValue:alphaValue];

    // If the window has been fully faded in, clean up the timer.
    if (alphaValue == 1.0) {
        [taskDrawTimer invalidate];
    }
}

/**
 * Updates the task description shown to the user.
 */
- (void) setTaskDescription:(NSString *)description
{
    NSShadow *textShadow = [[NSShadow alloc] init];
    [textShadow setShadowColor:[NSColor colorWithCalibratedWhite:0.0f alpha:0.75f]];
    [textShadow setShadowOffset:NSMakeSize(1.0f, -1.0f)];
    [textShadow setShadowBlurRadius:3.0f];

    NSMutableDictionary *attributes = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                                       [NSFont boldSystemFontOfSize:13.0f], NSFontAttributeName,
                                       textShadow, NSShadowAttributeName,
                                       nil];
    NSAttributedString *string = [[NSAttributedString alloc] initWithString:description attributes:attributes];

    [taskDescriptionText setAttributedStringValue:string];
}

/**
 * Sets the task percentage progress - the first call to this automatically
 * switches the progress display to determinate.
 * Can be called from background threads - forwards to main thread as appropriate.
 */
- (void) setTaskPercentage:(CGFloat)taskPercentage
{

    SPLog(@"setTaskPercentage = %f", taskPercentage);

    // If the task display is currently indeterminate, set it to determinate on the main thread.
    if (taskDisplayIsIndeterminate) {
        if (![NSThread isMainThread]) return [[self onMainThread] setTaskPercentage:taskPercentage];

        taskDisplayIsIndeterminate = NO;
        [taskProgressIndicator stopAnimation:self];
        [taskProgressIndicator setDoubleValue:0.5];
    }

    // Check the supplied progress.  Compare it to the display interval - how often
    // the interface is updated - and update the interface if the value has changed enough.
    taskProgressValue = taskPercentage;
    if (taskProgressValue >= taskDisplayLastValue + taskProgressValueDisplayInterval
        || taskProgressValue <= taskDisplayLastValue - taskProgressValueDisplayInterval)
    {
        if ([NSThread isMainThread]) {
            [taskProgressIndicator setDoubleValue:taskProgressValue];
        } else {
            [taskProgressIndicator performSelectorOnMainThread:@selector(setNumberValue:) withObject:[NSNumber numberWithDouble:taskProgressValue] waitUntilDone:NO];
        }
        taskDisplayLastValue = taskProgressValue;
    }
}

/**
 * Sets the task progress indicator back to indeterminate (also performed
 * automatically whenever a new task is started).
 * This can optionally be called with afterDelay set, in which case the intederminate
 * switch will be made after a short pause to minimise flicker for short actions.
 * Should be called on the main thread.
 */
- (void) setTaskProgressToIndeterminateAfterDelay:(BOOL)afterDelay
{
    SPLog(@"setTaskProgressToIndeterminateAfterDelay");

    if (afterDelay) {
        [self performSelector:@selector(setTaskProgressToIndeterminateAfterDelay:) withObject:nil afterDelay:0.5];
        return;
    }

    if (taskDisplayIsIndeterminate) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:taskProgressIndicator];
    taskDisplayIsIndeterminate = YES;
    [taskProgressIndicator setIndeterminate:YES];
    [taskProgressIndicator startAnimation:self];
    taskDisplayLastValue = 0;
}

/**
 * Hide the task progress and restore the document to allow actions again.
 */
- (void) endTask
{
    SPLog(@"endTask");

    // Ensure a call on the main thread
    if (![NSThread isMainThread]) return [[self onMainThread] endTask];

    SPLog(@"_isWorkingLevel = %li", (long)_isWorkingLevel);

    // Decrement the working level
    _isWorkingLevel--;
    assert(_isWorkingLevel >= 0);

    SPLog(@"_isWorkingLevel = %li", (long)_isWorkingLevel);

    // Ensure cancellation interface is reset
    [self disableTaskCancellation];

    // If all tasks have ended, re-enable the interface
    if (!_isWorkingLevel) {

        SPLog(@"!_isWorkingLevel, all tasks have ended");

        // Cancel the draw timer if it exists
        if (taskDrawTimer) {
            SPLog(@"Cancel the draw timer if it exists");
            [taskDrawTimer invalidate];
        }

        if (queryExecutionTimer) {
            queryStartDate = [[NSDate alloc] init];
            SPLog(@"self showQueryExecutionTime");
            [self showQueryExecutionTime];
            SPLog(@"queryExecutionTimer invalidate");
            [queryExecutionTimer invalidate];
        }

        // Hide the task interface and reset to indeterminate
        if (taskDisplayIsIndeterminate){
            SPLog(@"taskDisplayIsIndeterminate,stopAnimation ");
            [taskProgressIndicator stopAnimation:self];
        }
        [taskProgressWindow setAlphaValue:0.0f];
        [taskProgressWindow orderOut:self];
        taskDisplayIsIndeterminate = YES;
        [taskProgressIndicator setIndeterminate:YES];

        // Re-enable window interface
        databaseListIsSelectable = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:SPDocumentTaskEndNotification object:self];
        [self.mainToolbar validateVisibleItems];
        [chooseDatabaseButton setEnabled:_isConnected];
    }
}

/**
 * Allow a task to be cancelled, enabling the button with a supplied title
 * and optionally supplying a callback object and function.
 */
- (void) enableTaskCancellationWithTitle:(NSString *)buttonTitle callbackObject:(id)callbackObject callbackFunction:(SEL)callbackFunction
{
    // Ensure call on the main thread
    if (![NSThread isMainThread]) return [[self onMainThread] enableTaskCancellationWithTitle:buttonTitle callbackObject:callbackObject callbackFunction:callbackFunction];

    // If no task is active, return
    if (!_isWorkingLevel) return;

    if (callbackObject && callbackFunction) {
        taskCancellationCallbackObject = callbackObject;
        taskCancellationCallbackSelector = callbackFunction;
    }
    taskCanBeCancelled = YES;

    NSMutableAttributedString *colorTitle = [[NSMutableAttributedString alloc]
                                             initWithString:buttonTitle
                                             attributes:@{NSForegroundColorAttributeName: [NSColor whiteColor]}
                                             ];
    [taskCancelButton setAttributedTitle:colorTitle];
    [taskCancelButton setEnabled:YES];
    [taskCancelButton setHidden:NO];
}

/**
 * Disable task cancellation.  Called automatically at the end of a task.
 */
- (void)disableTaskCancellation
{
    // Ensure call on the main thread
    if (![NSThread isMainThread]) return [[self onMainThread] disableTaskCancellation];

    // If no task is active, return
    if (!_isWorkingLevel) return;

    taskCanBeCancelled = NO;
    taskCancellationCallbackObject = nil;
    taskCancellationCallbackSelector = NULL;
    [taskCancelButton setHidden:YES];
}

/**
 * Action sent by the cancel button when it's active.
 */
- (IBAction)cancelTask:(id)sender {
    if (!taskCanBeCancelled) return;

    [taskCancelButton setEnabled:NO];

    // See whether there is an active database structure task and whether it can be used
    // to cancel the query, for speed (no connection overhead!)
    if (databaseStructureRetrieval && [databaseStructureRetrieval connection]) {
        [mySQLConnection setLastQueryWasCancelled:YES];
        [[databaseStructureRetrieval connection] killQueryOnThreadID:[mySQLConnection mysqlConnectionThreadId]];
    } else {
        [mySQLConnection cancelCurrentQuery];
    }

    if (taskCancellationCallbackObject && taskCancellationCallbackSelector) {
        [taskCancellationCallbackObject performSelector:taskCancellationCallbackSelector];
    }
}

/**
 * Returns whether the document is busy performing a task - allows UI or actions
 * to be restricted as appropriate.
 */
- (BOOL)isWorking
{
    return (_isWorkingLevel > 0);
}

/**
 * Set whether the database list is selectable or not during the task process.
 */
- (void)setDatabaseListIsSelectable:(BOOL)isSelectable
{
    databaseListIsSelectable = isSelectable;
}

/**
 * Reposition the task window within the main window.
 */
- (void)centerTaskWindow
{
    NSPoint newBottomLeftPoint;
    NSRect mainWindowRect = [[self.parentWindowController window] frame];
    NSRect taskWindowRect = [taskProgressWindow frame];

    newBottomLeftPoint.x = roundf(mainWindowRect.origin.x + mainWindowRect.size.width/2 - taskWindowRect.size.width/2);
    newBottomLeftPoint.y = roundf(mainWindowRect.origin.y + mainWindowRect.size.height/2 - taskWindowRect.size.height/2);

    [taskProgressWindow setFrameOrigin:newBottomLeftPoint];
}

/**
 * Support pausing and restarting the task progress indicator.
 * Only works while the indicator is in indeterminate mode.
 */
- (void)setTaskIndicatorShouldAnimate:(BOOL)shouldAnimate
{
    if (shouldAnimate) {
        [[taskProgressIndicator onMainThread] startAnimation:self];
    } else {
        [[taskProgressIndicator onMainThread] stopAnimation:self];
    }
}

#pragma mark -
#pragma mark Encoding Methods

/**
 * Set the encoding for the database connection
 */
- (void)setConnectionEncoding:(NSString *)mysqlEncoding reloadingViews:(BOOL)reloadViews
{
    BOOL useLatin1Transport = NO;

    // Special-case UTF-8 over latin 1 to allow viewing/editing of mangled data.
    if ([mysqlEncoding isEqualToString:@"utf8-"]) {
        useLatin1Transport = YES;
        mysqlEncoding = @"utf8mb4";
    }

    // Set the connection encoding
    if (![mySQLConnection setEncoding:mysqlEncoding]) {
        NSLog(@"Error: could not set encoding to %@ nor fall back to database encoding on MySQL %@", mysqlEncoding, [self mySQLVersion]);
        return;
    }
    [mySQLConnection setEncodingUsesLatin1Transport:useLatin1Transport];

    // Update the selected menu item
    if (useLatin1Transport) {
        [[self onMainThread] updateEncodingMenuWithSelectedEncoding:[self encodingTagFromMySQLEncoding:[NSString stringWithFormat:@"%@-", mysqlEncoding]]];
    } else {
        [[self onMainThread] updateEncodingMenuWithSelectedEncoding:[self encodingTagFromMySQLEncoding:mysqlEncoding]];
    }

    // Update the stored connection encoding to prevent switches
    [mySQLConnection storeEncodingForRestoration];

    // Reload views as appropriate
    if (reloadViews) {
        [self setStructureRequiresReload:YES];
        [self setContentRequiresReload:YES];
        [self setStatusRequiresReload:YES];
    }
}

/**
 * updates the currently selected item in the encoding menu
 *
 * @param NSString *encoding - the title of the menu item which will be selected
 */
- (void)updateEncodingMenuWithSelectedEncoding:(NSNumber *)encodingTag
{
    NSInteger itemToSelect = [encodingTag integerValue];
    NSInteger correctStateForMenuItem;

    for (NSMenuItem *aMenuItem in [selectEncodingMenu itemArray]) {
        correctStateForMenuItem = ([aMenuItem tag] == itemToSelect) ? NSControlStateValueOn : NSControlStateValueOff;

        if ([aMenuItem state] == correctStateForMenuItem) continue; // don't re-apply state incase it causes performance issues

        [aMenuItem setState:correctStateForMenuItem];
    }
}

/**
 * Returns the display name for a mysql encoding
 */
- (NSNumber *)encodingTagFromMySQLEncoding:(NSString *)mysqlEncoding
{
    NSDictionary *translationMap = @{
        @"ucs2"     : @(SPEncodingUCS2),
        @"utf8"     : @(SPEncodingUTF8),
        @"utf8-"    : @(SPEncodingUTF8viaLatin1),
        @"ascii"    : @(SPEncodingASCII),
        @"latin1"   : @(SPEncodingLatin1),
        @"macroman" : @(SPEncodingMacRoman),
        @"cp1250"   : @(SPEncodingCP1250Latin2),
        @"latin2"   : @(SPEncodingISOLatin2),
        @"cp1256"   : @(SPEncodingCP1256Arabic),
        @"greek"    : @(SPEncodingGreek),
        @"hebrew"   : @(SPEncodingHebrew),
        @"latin5"   : @(SPEncodingLatin5Turkish),
        @"cp1257"   : @(SPEncodingCP1257WinBaltic),
        @"cp1251"   : @(SPEncodingCP1251WinCyrillic),
        @"big5"     : @(SPEncodingBig5Chinese),
        @"sjis"     : @(SPEncodingShiftJISJapanese),
        @"ujis"     : @(SPEncodingEUCJPJapanese),
        @"euckr"    : @(SPEncodingEUCKRKorean),
        @"utf8mb4"  : @(SPEncodingUTF8MB4)
    };
    NSNumber *encodingTag = [translationMap valueForKey:mysqlEncoding];

    if (!encodingTag)
        return @(SPEncodingAutodetect);

    return encodingTag;
}

/**
 * Returns the mysql encoding for an encoding string that is displayed to the user
 */
- (NSString *)mysqlEncodingFromEncodingTag:(NSNumber *)encodingTag
{
    NSDictionary *translationMap = [NSDictionary dictionaryWithObjectsAndKeys:
                                    @"ucs2",     [NSString stringWithFormat:@"%i", SPEncodingUCS2],
                                    @"utf8",     [NSString stringWithFormat:@"%i", SPEncodingUTF8],
                                    @"utf8-",    [NSString stringWithFormat:@"%i", SPEncodingUTF8viaLatin1],
                                    @"ascii",    [NSString stringWithFormat:@"%i", SPEncodingASCII],
                                    @"latin1",   [NSString stringWithFormat:@"%i", SPEncodingLatin1],
                                    @"macroman", [NSString stringWithFormat:@"%i", SPEncodingMacRoman],
                                    @"cp1250",   [NSString stringWithFormat:@"%i", SPEncodingCP1250Latin2],
                                    @"latin2",   [NSString stringWithFormat:@"%i", SPEncodingISOLatin2],
                                    @"cp1256",   [NSString stringWithFormat:@"%i", SPEncodingCP1256Arabic],
                                    @"greek",    [NSString stringWithFormat:@"%i", SPEncodingGreek],
                                    @"hebrew",   [NSString stringWithFormat:@"%i", SPEncodingHebrew],
                                    @"latin5",   [NSString stringWithFormat:@"%i", SPEncodingLatin5Turkish],
                                    @"cp1257",   [NSString stringWithFormat:@"%i", SPEncodingCP1257WinBaltic],
                                    @"cp1251",   [NSString stringWithFormat:@"%i", SPEncodingCP1251WinCyrillic],
                                    @"big5",     [NSString stringWithFormat:@"%i", SPEncodingBig5Chinese],
                                    @"sjis",     [NSString stringWithFormat:@"%i", SPEncodingShiftJISJapanese],
                                    @"ujis",     [NSString stringWithFormat:@"%i", SPEncodingEUCJPJapanese],
                                    @"euckr",    [NSString stringWithFormat:@"%i", SPEncodingEUCKRKorean],
                                    @"utf8mb4",  [NSString stringWithFormat:@"%i", SPEncodingUTF8MB4],
                                    nil];
    NSString *mysqlEncoding = [translationMap valueForKey:[NSString stringWithFormat:@"%i", [encodingTag intValue]]];

    if (!mysqlEncoding) return @"utf8mb4";

    return mysqlEncoding;
}

/**
 * Retrieve the current database encoding.  This will return Latin-1
 * for unknown encodings.
 */
- (NSString *)databaseEncoding
{
    return selectedDatabaseEncoding;
}

/**
 * Detect and store the encoding of the currently selected database.
 * Falls back to Latin-1 if the encoding cannot be retrieved.
 */
- (void)detectDatabaseEncoding
{
    _supportsEncoding = YES;

    NSString *mysqlEncoding = [databaseDataInstance getDatabaseDefaultCharacterSet];



    // Fallback or older version? -> set encoding to mysql default encoding latin1
    if ( !mysqlEncoding ) {
        NSLog(@"Error: no character encoding found for db, mysql version is %@", [self mySQLVersion]);

        selectedDatabaseEncoding = @"latin1";

        _supportsEncoding = NO;
    }
    else {
        selectedDatabaseEncoding = mysqlEncoding;
    }
}

/**
 * When sent by an NSMenuItem, will set the encoding based on the title of the menu item
 */
- (void)chooseEncoding:(id)sender {
    [self setConnectionEncoding:[self mysqlEncodingFromEncodingTag:[NSNumber numberWithInteger:[(NSMenuItem *)sender tag]]] reloadingViews:YES];
}

/**
 * return YES if MySQL server supports choosing connection and table encodings (MySQL 4.1 and newer)
 */
- (BOOL)supportsEncoding
{
    return _supportsEncoding;
}

#pragma mark -
#pragma mark Table Methods

/**
 * Copies if sender == self or displays or the CREATE TABLE syntax of the selected table(s) to the user .
 */
- (void)showCreateTableSyntax:(SPDatabaseDocument *)sender {
    NSInteger colOffs = 1;
    NSString *query = nil;
    NSString *typeString = @"";
    NSString *header = @"";
    NSMutableString *createSyntax = [NSMutableString string];

    NSIndexSet *indexes = [[tablesListInstance valueForKeyPath:@"tablesListView"] selectedRowIndexes];

    NSUInteger currentIndex = [indexes firstIndex];
    NSUInteger counter = 0;
    NSInteger type;

    NSArray *types = [tablesListInstance selectedTableTypes];
    NSArray *items = [tablesListInstance selectedTableItems];

    while (currentIndex != NSNotFound)
    {
        type = [[types objectAtIndex:counter] intValue];
        query = nil;

        if( type == SPTableTypeTable ) {
            query = [NSString stringWithFormat:@"SHOW CREATE TABLE %@", [[items objectAtIndex:counter] backtickQuotedString]];
            typeString = @"TABLE";
        }
        else if( type == SPTableTypeView ) {
            query = [NSString stringWithFormat:@"SHOW CREATE VIEW %@", [[items objectAtIndex:counter] backtickQuotedString]];
            typeString = @"VIEW";
        }
        else if( type == SPTableTypeProc ) {
            query = [NSString stringWithFormat:@"SHOW CREATE PROCEDURE %@", [[items objectAtIndex:counter] backtickQuotedString]];
            typeString = @"PROCEDURE";
            colOffs = 2;
        }
        else if( type == SPTableTypeFunc ) {
            query = [NSString stringWithFormat:@"SHOW CREATE FUNCTION %@", [[items objectAtIndex:counter] backtickQuotedString]];
            typeString = @"FUNCTION";
            colOffs = 2;
        }

        if (query == nil) {
            NSLog(@"Unknown type for selected item while getting the create syntax for '%@'", [items objectAtIndex:counter]);
            NSBeep();
            return;
        }

        SPMySQLResult *theResult = [mySQLConnection queryString:query];
        [theResult setReturnDataAsStrings:YES];

        // Check for errors, only displaying if the connection hasn't been terminated
        if ([mySQLConnection queryErrored]) {
            if ([mySQLConnection isConnected]) {
                [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error", @"error message title") message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while creating table syntax.\n\n: %@", @"Error shown when unable to show create table syntax"), [mySQLConnection lastErrorMessage]] callback:nil];
            }

            return;
        }

        NSString *tableSyntax;
        if (type == SPTableTypeProc) tableSyntax = [NSString stringWithFormat:@"DELIMITER ;;\n%@;;\nDELIMITER ", [[theResult getRowAsArray] objectAtIndex:colOffs]];
        else                         tableSyntax = [[theResult getRowAsArray] objectAtIndex:colOffs];

        // A NULL value indicates that the user does not have permission to view the syntax
        if ([tableSyntax isNSNull]) {
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Permission Denied", @"Permission Denied") message:NSLocalizedString(@"The creation syntax could not be retrieved due to a permissions error.\n\nPlease check your user permissions with an administrator.", @"Create syntax permission denied detail") callback:nil];
            return;
        }

        if([indexes count] > 1)
            header = [NSString stringWithFormat:@"-- Create syntax for %@ '%@'\n", typeString, [items objectAtIndex:counter]];

        [createSyntax appendFormat:@"%@%@;%@", header, (type == SPTableTypeView) ? [tableSyntax createViewSyntaxPrettifier] : tableSyntax, (counter < [indexes count]-1) ? @"\n\n" : @""];

        counter++;

        // Get next index (beginning from the end)
        currentIndex = [indexes indexGreaterThanIndex:currentIndex];

    }

    // copy to the clipboard if sender was self, otherwise
    // show syntax(es) in sheet
    if (sender == self) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb declareTypes:@[NSPasteboardTypeString] owner:self];
        [pb setString:createSyntax forType:NSPasteboardTypeString];

        // Table syntax copied notification
        NSUserNotification *notification = [[NSUserNotification alloc] init];
        notification.title = @"Syntax Copied";
        notification.informativeText=[NSString stringWithFormat:NSLocalizedString(@"Syntax for %@ table copied", @"description for table syntax copied notification"), [self table]];
        notification.soundName = NSUserNotificationDefaultSoundName;

        [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];

        return;
    }

    if ([indexes count] == 1) [createTableSyntaxTextField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Create syntax for %@ '%@'", @"Create syntax label"), typeString, [self table]]];
    else                      [createTableSyntaxTextField setStringValue:NSLocalizedString(@"Create syntaxes for selected items", @"Create syntaxes for selected items label")];

    [createTableSyntaxTextView setEditable:YES];
    [createTableSyntaxTextView setString:@""];
    [createTableSyntaxTextView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:createSyntax]];
    [createTableSyntaxTextView setEditable:NO];

    [createTableSyntaxWindow makeFirstResponder:createTableSyntaxTextField];

    // Show variables sheet
    [[self.parentWindowController window] beginSheet:createTableSyntaxWindow completionHandler:nil];
}

/**
 * Copies the CREATE TABLE syntax of the selected table to the pasteboard.
 */
- (void)copyCreateTableSyntax:(SPDatabaseDocument *)sender {
    [self showCreateTableSyntax:self];

    return;
}

/**
 * Performs a MySQL check table on the selected table and presents the result to the user via an alert sheet.
 */
- (void)checkTable {
    NSArray *selectedItems = [tablesListInstance selectedTableItems];
    id message = nil;

    if([selectedItems count] == 0) return;

    SPMySQLResult *theResult = [mySQLConnection queryString:[NSString stringWithFormat:@"CHECK TABLE %@", [selectedItems componentsJoinedAndBacktickQuoted]]];
    [theResult setReturnDataAsStrings:YES];

    NSString *what = ([selectedItems count]>1) ? NSLocalizedString(@"selected items", @"selected items") : [NSString stringWithFormat:@"%@ '%@'", NSLocalizedString(@"table", @"table"), [self table]];

    // Check for errors, only displaying if the connection hasn't been terminated
    if ([mySQLConnection queryErrored]) {
        NSString *mText = ([selectedItems count]>1) ? NSLocalizedString(@"Unable to check selected items", @"unable to check selected items message") : NSLocalizedString(@"Unable to check table", @"unable to check table message");
        if ([mySQLConnection isConnected]) {
            [NSAlert createWarningAlertWithTitle:mText message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while trying to check the %@.\n\nMySQL said:%@",@"an error occurred while trying to check the %@.\n\nMySQL said:%@"), what, [mySQLConnection lastErrorMessage]] callback:nil];
        }

        return;
    }

    NSArray *resultStatuses = [theResult getAllRows];
    BOOL statusOK = YES;
    for (NSDictionary *eachRow in theResult) {
        if (![[eachRow objectForKey:@"Msg_type"] isEqualToString:@"status"]) {
            statusOK = NO;
            break;
        }
    }

    // Process result
    if([selectedItems count] == 1) {
        NSDictionary *lastresult = [resultStatuses lastObject];

        message = ([[lastresult objectForKey:@"Msg_type"] isEqualToString:@"status"]) ? NSLocalizedString(@"Check table successfully passed.",@"check table successfully passed message") : NSLocalizedString(@"Check table failed.", @"check table failed message");

        message = [NSString stringWithFormat:NSLocalizedString(@"%@\n\nMySQL said: %@", @"Error display text, showing original MySQL error"), message, [lastresult objectForKey:@"Msg_text"]];
    } else if(statusOK) {
        message = NSLocalizedString(@"Check of all selected items successfully passed.",@"check of all selected items successfully passed message");
    }

    if(message) {
        [NSAlert createWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Check %@", @"CHECK one or more tables - result title"), what] message:message callback:nil];
    } else {
        message = NSLocalizedString(@"MySQL said:",@"mysql said message");
        statusValues = resultStatuses;

        [NSAlert createAccessoryWarningAlertWithTitle:NSLocalizedString(@"Error while checking selected items", @"error while checking selected items message") message:message accessoryView:statusTableAccessoryView callback:^{
            if (self->statusValues) {
                self->statusValues = nil;
            }
        }];
    }
}

/**
 * Analyzes the selected table and presents the result to the user via an alert sheet.
 */
- (void)analyzeTable {
    NSArray *selectedItems = [tablesListInstance selectedTableItems];
    id message = nil;

    if([selectedItems count] == 0) return;

    SPMySQLResult *theResult = [mySQLConnection queryString:[NSString stringWithFormat:@"ANALYZE TABLE %@", [selectedItems componentsJoinedAndBacktickQuoted]]];
    [theResult setReturnDataAsStrings:YES];

    NSString *what = ([selectedItems count]>1) ? NSLocalizedString(@"selected items", @"selected items") : [NSString stringWithFormat:@"%@ '%@'", NSLocalizedString(@"table", @"table"), [self table]];

    // Check for errors, only displaying if the connection hasn't been terminated
    if ([mySQLConnection queryErrored]) {
        NSString *mText = ([selectedItems count]>1) ? NSLocalizedString(@"Unable to analyze selected items", @"unable to analyze selected items message") : NSLocalizedString(@"Unable to analyze table", @"unable to analyze table message");
        if ([mySQLConnection isConnected]) {
            [NSAlert createWarningAlertWithTitle:mText message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while analyzing the %@.\n\nMySQL said:%@",@"an error occurred while analyzing the %@.\n\nMySQL said:%@"), what, [mySQLConnection lastErrorMessage]] callback:nil];
        }

        return;
    }

    NSArray *resultStatuses = [theResult getAllRows];
    BOOL statusOK = YES;
    for (NSDictionary *eachRow in resultStatuses) {
        if(![[eachRow objectForKey:@"Msg_type"] isEqualToString:@"status"]) {
            statusOK = NO;
            break;
        }
    }

    // Process result
    if([selectedItems count] == 1) {
        NSDictionary *lastresult = [resultStatuses lastObject];

        message = ([[lastresult objectForKey:@"Msg_type"] isEqualToString:@"status"]) ? NSLocalizedString(@"Successfully analyzed table.",@"analyze table successfully passed message") : NSLocalizedString(@"Analyze table failed.", @"analyze table failed message");

        message = [NSString stringWithFormat:NSLocalizedString(@"%@\n\nMySQL said: %@", @"Error display text, showing original MySQL error"), message, [lastresult objectForKey:@"Msg_text"]];
    } else if(statusOK) {
        message = NSLocalizedString(@"Successfully analyzed all selected items.",@"successfully analyzed all selected items message");
    }

    if(message) {
        [NSAlert createWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Analyze %@", @"ANALYZE one or more tables - result title"), what] message:message callback:nil];
    } else {
        message = NSLocalizedString(@"MySQL said:",@"mysql said message");

        statusValues = resultStatuses;
        [NSAlert createAccessoryWarningAlertWithTitle:NSLocalizedString(@"Error while analyzing selected items", @"error while analyzing selected items message") message:message accessoryView:statusTableAccessoryView callback:^{
            if (self->statusValues) {
                self->statusValues = nil;
            }
        }];
    }
}

/**
 * Optimizes the selected table and presents the result to the user via an alert sheet.
 */
- (void)optimizeTable {

    NSArray *selectedItems = [tablesListInstance selectedTableItems];
    id message = nil;

    if([selectedItems count] == 0) return;

    SPMySQLResult *theResult = [mySQLConnection queryString:[NSString stringWithFormat:@"OPTIMIZE TABLE %@", [selectedItems componentsJoinedAndBacktickQuoted]]];
    [theResult setReturnDataAsStrings:YES];

    NSString *what = ([selectedItems count]>1) ? NSLocalizedString(@"selected items", @"selected items") : [NSString stringWithFormat:@"%@ '%@'", NSLocalizedString(@"table", @"table"), [self table]];

    // Check for errors, only displaying if the connection hasn't been terminated
    if ([mySQLConnection queryErrored]) {
        NSString *mText = ([selectedItems count]>1) ? NSLocalizedString(@"Unable to optimze selected items", @"unable to optimze selected items message") : NSLocalizedString(@"Unable to optimze table", @"unable to optimze table message");
        if ([mySQLConnection isConnected]) {
            [NSAlert createWarningAlertWithTitle:mText message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while optimzing the %@.\n\nMySQL said:%@",@"an error occurred while trying to optimze the %@.\n\nMySQL said:%@"), what, [mySQLConnection lastErrorMessage]] callback:nil];
        }
        return;
    }

    NSArray *resultStatuses = [theResult getAllRows];
    BOOL statusOK = YES;
    for (NSDictionary *eachRow in resultStatuses) {
        if (![[eachRow objectForKey:@"Msg_type"] isEqualToString:@"status"]) {
            statusOK = NO;
            break;
        }
    }

    // Process result
    if([selectedItems count] == 1) {
        NSDictionary *lastresult = [resultStatuses lastObject];

        message = ([[lastresult objectForKey:@"Msg_type"] isEqualToString:@"status"]) ? NSLocalizedString(@"Successfully optimized table.",@"optimize table successfully passed message") : NSLocalizedString(@"Optimize table failed.", @"optimize table failed message");

        message = [NSString stringWithFormat:NSLocalizedString(@"%@\n\nMySQL said: %@", @"Error display text, showing original MySQL error"), message, [lastresult objectForKey:@"Msg_text"]];
    } else if(statusOK) {
        message = NSLocalizedString(@"Successfully optimized all selected items.",@"successfully optimized all selected items message");
    }

    if(message) {
        [NSAlert createWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Optimize %@", @"OPTIMIZE one or more tables - result title"), what] message:message callback:nil];
    } else {
        message = NSLocalizedString(@"MySQL said:",@"mysql said message");

        statusValues = resultStatuses;

        [NSAlert createAccessoryWarningAlertWithTitle:NSLocalizedString(@"Error while optimizing selected items", @"error while optimizing selected items message") message:message accessoryView:statusTableAccessoryView callback:^{
            if (self->statusValues) {
                self->statusValues = nil;
            }
        }];
    }
}

/**
 * Repairs the selected table and presents the result to the user via an alert sheet.
 */
- (void)repairTable {
    NSArray *selectedItems = [tablesListInstance selectedTableItems];
    id message = nil;

    if([selectedItems count] == 0) return;

    SPMySQLResult *theResult = [mySQLConnection queryString:[NSString stringWithFormat:@"REPAIR TABLE %@", [selectedItems componentsJoinedAndBacktickQuoted]]];
    [theResult setReturnDataAsStrings:YES];

    NSString *what = ([selectedItems count]>1) ? NSLocalizedString(@"selected items", @"selected items") : [NSString stringWithFormat:@"%@ '%@'", NSLocalizedString(@"table", @"table"), [self table]];

    // Check for errors, only displaying if the connection hasn't been terminated
    if ([mySQLConnection queryErrored]) {
        NSString *mText = ([selectedItems count]>1) ? NSLocalizedString(@"Unable to repair selected items", @"unable to repair selected items message") : NSLocalizedString(@"Unable to repair table", @"unable to repair table message");
        if ([mySQLConnection isConnected]) {
            [NSAlert createWarningAlertWithTitle:mText message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while repairing the %@.\n\nMySQL said:%@",@"an error occurred while trying to repair the %@.\n\nMySQL said:%@"), what, [mySQLConnection lastErrorMessage]] callback:nil];
        }
        return;
    }

    NSArray *resultStatuses = [theResult getAllRows];
    BOOL statusOK = YES;
    for (NSDictionary *eachRow in resultStatuses) {
        if (![[eachRow objectForKey:@"Msg_type"] isEqualToString:@"status"]) {
            statusOK = NO;
            break;
        }
    }

    // Process result
    if([selectedItems count] == 1) {
        NSDictionary *lastresult = [resultStatuses lastObject];

        message = ([[lastresult objectForKey:@"Msg_type"] isEqualToString:@"status"]) ? NSLocalizedString(@"Successfully repaired table.",@"repair table successfully passed message") : NSLocalizedString(@"Repair table failed.", @"repair table failed message");

        message = [NSString stringWithFormat:NSLocalizedString(@"%@\n\nMySQL said: %@", @"Error display text, showing original MySQL error"), message, [lastresult objectForKey:@"Msg_text"]];
    } else if(statusOK) {
        message = NSLocalizedString(@"Successfully repaired all selected items.",@"successfully repaired all selected items message");
    }

    if(message) {
        [NSAlert createWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Repair %@", @"REPAIR one or more tables - result title"), what] message:message callback:nil];
    } else {
        message = NSLocalizedString(@"MySQL said:",@"mysql said message");

        statusValues = resultStatuses;

        [NSAlert createAccessoryWarningAlertWithTitle:NSLocalizedString(@"Error while repairing selected items", @"error while repairing selected items message") message:message accessoryView:statusTableAccessoryView callback:^{
            if (self->statusValues) {
                self->statusValues = nil;
            }
        }];
    }
}

/**
 * Flush the selected table and inform the user via a dialog sheet.
 */
- (void)flushTable {
    NSArray *selectedItems = [tablesListInstance selectedTableItems];
    id message = nil;

    if([selectedItems count] == 0) return;

    SPMySQLResult *theResult = [mySQLConnection queryString:[NSString stringWithFormat:@"FLUSH TABLE %@", [selectedItems componentsJoinedAndBacktickQuoted]]];
    [theResult setReturnDataAsStrings:YES];

    NSString *what = ([selectedItems count]>1) ? NSLocalizedString(@"selected items", @"selected items") : [NSString stringWithFormat:@"%@ '%@'", NSLocalizedString(@"table", @"table"), [self table]];

    // Check for errors, only displaying if the connection hasn't been terminated
    if ([mySQLConnection queryErrored]) {
        NSString *mText = ([selectedItems count]>1) ? NSLocalizedString(@"Unable to flush selected items", @"unable to flush selected items message") : NSLocalizedString(@"Unable to flush table", @"unable to flush table message");
        if ([mySQLConnection isConnected]) {
            [NSAlert createWarningAlertWithTitle:mText message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while flushing the %@.\n\nMySQL said:%@",@"an error occurred while trying to flush the %@.\n\nMySQL said:%@"), what, [mySQLConnection lastErrorMessage]] callback:nil];
        }

        return;
    }

    NSArray *resultStatuses = [theResult getAllRows];
    BOOL statusOK = YES;
    for (NSDictionary *eachRow in resultStatuses) {
        if (![[eachRow objectForKey:@"Msg_type"] isEqualToString:@"status"]) {
            statusOK = NO;
            break;
        }
    }

    // Process result
    if([selectedItems count] == 1) {
        NSDictionary *lastresult = [resultStatuses lastObject];

        message = ([[lastresult objectForKey:@"Msg_type"] isEqualToString:@"status"]) ? NSLocalizedString(@"Successfully flushed table.",@"flush table successfully passed message") : NSLocalizedString(@"Flush table failed.", @"flush table failed message");

        message = [NSString stringWithFormat:NSLocalizedString(@"%@\n\nMySQL said: %@", @"Error display text, showing original MySQL error"), message, [lastresult objectForKey:@"Msg_text"]];
    } else if(statusOK) {
        message = NSLocalizedString(@"Successfully flushed all selected items.",@"successfully flushed all selected items message");
    }

    if(message) {
        [NSAlert createWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Flush %@", @"FLUSH one or more tables - result title"), what] message:message callback:nil];
    } else {
        message = NSLocalizedString(@"MySQL said:",@"mysql said message");

        statusValues = resultStatuses;

        [NSAlert createAccessoryWarningAlertWithTitle:NSLocalizedString(@"Error while flushing selected items", @"error while flushing selected items message") message:message accessoryView:statusTableAccessoryView callback:^{
            if (self->statusValues) {
                self->statusValues = nil;
            }
        }];
    }
}

/**
 * Runs a MySQL checksum on the selected table and present the result to the user via an alert sheet.
 */
- (void)checksumTable {
    NSArray *selectedItems = [tablesListInstance selectedTableItems];
    id message = nil;

    if([selectedItems count] == 0) return;

    SPMySQLResult *theResult = [mySQLConnection queryString:[NSString stringWithFormat:@"CHECKSUM TABLE %@", [selectedItems componentsJoinedAndBacktickQuoted]]];

    NSString *what = ([selectedItems count]>1) ? NSLocalizedString(@"selected items", @"selected items") : [NSString stringWithFormat:@"%@ '%@'", NSLocalizedString(@"table", @"table"), [self table]];

    // Check for errors, only displaying if the connection hasn't been terminated
    if ([mySQLConnection queryErrored]) {
        if ([mySQLConnection isConnected]) {
            NSString *alertMessage = [NSString stringWithFormat:NSLocalizedString(@"An error occurred while performing the checksum on %@.\n\nMySQL said:%@",@"an error occurred while performing the checksum on the %@.\n\nMySQL said:%@"), what, [mySQLConnection lastErrorMessage]];
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Unable to perform the checksum", @"unable to perform the checksum") message:alertMessage callback:nil];
        }

        return;
    }

    // Process result
    NSArray *resultStatuses = [theResult getAllRows];
    if([selectedItems count] == 1) {
        message = [[resultStatuses lastObject] objectForKey:@"Checksum"];
        NSString *alertMessage = [NSString stringWithFormat:NSLocalizedString(@"Table checksum: %@", @"table checksum: %@"), message];
        [NSAlert createWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Checksum %@", @"checksum %@ message"), what] message:alertMessage callback:nil];
    } else {

        statusValues = resultStatuses;

        [NSAlert createAccessoryWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Checksums of %@",@"Checksums of %@ message"), what] message:message accessoryView:statusTableAccessoryView callback:^{
            if (self->statusValues) {
                self->statusValues = nil;
            }
        }];
    }
}

/**
 * Saves the current tables create syntax to the selected file.
 */
- (IBAction)saveCreateSyntax:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];

    [panel setAllowedFileTypes:@[SPFileExtensionSQL]];

    [panel setExtensionHidden:NO];
    [panel setAllowsOtherFileTypes:YES];
    [panel setCanSelectHiddenExtension:YES];

    [panel setNameFieldStringValue:[NSString stringWithFormat:@"CreateSyntax-%@", [self table]]];
    [panel beginSheetModalForWindow:createTableSyntaxWindow completionHandler:^(NSInteger returnCode) {
        if (returnCode == NSModalResponseOK) {
            NSString *createSyntax = [self->createTableSyntaxTextView string];

            if ([createSyntax length] > 0) {
                NSString *output = [NSString stringWithFormat:@"-- %@ '%@'\n\n%@\n", NSLocalizedString(@"Create syntax for", @"create syntax for table comment"), [self table], createSyntax];

                [output writeToURL:[panel URL] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            }
        }
    }];
}

/**
 * Copy the create syntax in the create syntax text view to the pasteboard.
 */
- (IBAction)copyCreateTableSyntaxFromSheet:(id)sender
{
    NSString *createSyntax = [createTableSyntaxTextView string];

    if ([createSyntax length] > 0) {
        // Copy to the clipboard
        NSPasteboard *pb = [NSPasteboard generalPasteboard];

        [pb declareTypes:@[NSPasteboardTypeString] owner:self];
        [pb setString:createSyntax forType:NSPasteboardTypeString];

        // Table syntax copied notification
        NSUserNotification *notification = [[NSUserNotification alloc] init];
        notification.title = @"Syntax Copied";
        notification.informativeText=[NSString stringWithFormat:NSLocalizedString(@"Syntax for %@ table copied", @"description for table syntax copied notification"), [self table]];
        notification.soundName = NSUserNotificationDefaultSoundName;

        [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
    }
}

/**
 * Switches to the content view and makes the filter field the first responder (has focus).
 */
- (void)focusOnTableContentFilter {
    [self viewContent];

    [tableContentInstance performSelector:@selector(makeContentFilterHaveFocus) withObject:nil afterDelay:0.1];
}

/**
 * Switches to the content view and makes the advanced filter view the first responder
 */
- (void)showFilterTable {
    [self viewContent];

    [tableContentInstance toggleRuleEditorVisible:nil];
}

/**
 * Allow Command-F to set the focus to the content view filter if that view is active
 */
- (void)performFindPanelAction:(id)sender
{
    [tableContentInstance makeContentFilterHaveFocus];
}

/**
 * Exports the selected tables in the chosen file format.
 */

- (IBAction)exportSelectedTablesAs:(id)sender
{
    [exportControllerInstance exportTables:[tablesListInstance selectedTableItems] asFormat:[sender tag] usingSource:SPTableExport];
}

/**
 * Opens the data export dialog.
 */
- (void)exportData {
    if (_isConnected) {
        [exportControllerInstance exportData];
    }
}

#pragma mark -
#pragma mark Other Methods

- (IBAction)multipleLineEditingButtonClicked:(NSButton *)sender{
    SPLog(@"multipleLineEditingButtonClicked. State: %ld",(long)[sender state]);
    user_defaults_set_bool(SPEditInSheetEnabled,[sender state]);
}

/**
 * Set that query which will be inserted into the Query Editor
 * after establishing the connection
 */

- (void)initQueryEditorWithString:(NSString *)query
{
    queryEditorInitString = query;
}

/**
 * Invoked when user hits the cancel button or close button in
 * dialogs such as the variableSheet or the createTableSyntaxSheet
 */
- (IBAction)closeSheet:(id)sender
{
    [NSApp stopModalWithCode:0];
}

/**
 * Closes either the server variables or create syntax sheets.
 */
- (IBAction)closePanelSheet:(id)sender
{
    [NSApp endSheet:[sender window] returnCode:[sender tag]];
    [[sender window] orderOut:self];
}

/**
 * Displays the user account manager.
 */
- (void)showUserManager {
    if (!userManagerInstance) {
        userManagerInstance = [[SPUserManager alloc] init];

        [userManagerInstance setDatabaseDocument:self];
        [userManagerInstance setConnection:mySQLConnection];
        [userManagerInstance setServerSupport:serverSupport];
    }

    // Before displaying the user manager make sure the current user has access to the mysql.user table.
    SPMySQLResult *result = [mySQLConnection queryString:@"SELECT user FROM mysql.user LIMIT 1"];

    if ([mySQLConnection queryErrored] && ([result numberOfRows] == 0)) {

        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Unable to get list of users", @"unable to get list of users message") message:NSLocalizedString(@"An error occurred while trying to get the list of users. Please make sure you have the necessary privileges to perform user management, including access to the mysql.user table.", @"unable to get list of users informative message") callback:nil];
        return;
    }

    [userManagerInstance beginSheetModalForWindow:[self.parentWindowController window] completionHandler:^(){
        //Release the UserManager instance after completion
        self->userManagerInstance = nil;
    }];
}

/**
 * Passes query to tablesListInstance
 */
- (void)doPerformQueryService:(NSString *)query {
    [self viewQuery];
    [customQueryInstance doPerformQueryService:query];
}

/**
 * Inserts query into the Custom Query editor
 */
- (void)doPerformLoadQueryService:(NSString *)query {
    [self viewQuery];
    [customQueryInstance doPerformLoadQueryService:query];
}

/**
 * Flushes the mysql privileges
 */
- (void)flushPrivileges {
    [mySQLConnection queryString:@"FLUSH PRIVILEGES"];

    if (![mySQLConnection queryErrored]) {
        //flushed privileges without errors
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Flushed Privileges", @"title of panel when successfully flushed privs") message:NSLocalizedString(@"Successfully flushed privileges.", @"message of panel when successfully flushed privs") callback:nil];
    } else {
        //error while flushing privileges
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error", @"error") message:[NSString stringWithFormat:NSLocalizedString(@"Couldn't flush privileges.\nMySQL said: %@", @"message of panel when flushing privs failed"), [mySQLConnection lastErrorMessage]] callback:nil];
    }
}

/**
 * Ask the connection controller to initiate connection, if it hasn't
 * already.  Used to support automatic connections on window open,
 */
- (void)connect
{
    SPLog(@"connect in dbdoc");

    if (mySQLVersion) return;
    [connectionController initiateConnection:self];
}

- (void)closeConnection {
    SPLog(@"closeConnection");
    [mySQLConnection setDelegate:nil];

    SPLog(@"Closing mySQLConnection");
    [mySQLConnection disconnect];
  
    SPLog(@"Closing databaseStructureRetrieval");
    [[databaseStructureRetrieval connection] disconnect];

    _isConnected = NO;

    // Disconnected notification
    NSUserNotification *notification = [[NSUserNotification alloc] init];
    notification.title = @"Disconnected";
    notification.soundName = NSUserNotificationDefaultSoundName;

    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}

/**
 * This method is called as part of Key Value Observing which is used to watch for prefernce changes which effect the interface.
 */
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:SPConsoleEnableLogging]) {
        [mySQLConnection setDelegateQueryLogging:[[change objectForKey:NSKeyValueChangeNewKey] boolValue]];
    }
    else if ([keyPath isEqualToString:SPEditInSheetEnabled]) {
        multipleLineEditingButton.state = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
    }
}

- (SPHelpViewerClient *)helpViewerClient
{
    return helpViewerClientInstance;
}

/**
 * Is current document Untitled?
 */
- (BOOL)isUntitled
{
    return (!_isSavedInBundle && [self fileURL] && [[self fileURL] isFileURL]) ? NO : YES;
}

/**
 * Asks any currently editing views to commit their changes;
 * returns YES if changes were successfully committed, and NO
 * if an error occurred or user interaction is required.
 */
- (BOOL)couldCommitCurrentViewActions
{
    [[self.parentWindowController window] endEditingFor:nil];
    switch ([self currentlySelectedView]) {

        case SPTableViewStructure:
            return [tableSourceInstance saveRowOnDeselect];

        case SPTableViewContent:
            return [tableContentInstance saveRowOnDeselect];

        default:
            break;
    }

    return YES;
}

#pragma mark -
#pragma mark Accessor methods

/**
 * Returns the host
 */
- (NSString *)host
{
    if ([connectionController type] == SPSocketConnection) return @"localhost";

    NSString *host = [connectionController host];

    if (!host) host = @"";

    return host;
}

/**
 * Returns the name
 */
- (NSString *)name
{
    if ([connectionController name] && [[connectionController name] length]) {
        return [connectionController name];
    }

    if ([connectionController type] == SPSocketConnection) {
        return [NSString stringWithFormat:@"%@@localhost", ([connectionController user] && [[connectionController user] length])?[connectionController user]:@"anonymous"];
    }

    return [NSString stringWithFormat:@"%@@%@", ([connectionController user] && [[connectionController user] length])?[connectionController user]:@"anonymous", [connectionController host]?[connectionController host]:@""];
}

/**
 * Returns a string to identify the connection uniquely (mainly used to set up db structure with unique keys)
 */
- (NSString *)connectionID
{
    if (!_isConnected) return @"_";

    NSString *port = [[self port] length] ? [NSString stringWithFormat:@":%@", [self port]] : @"";

    switch ([connectionController type])
    {
        case SPSocketConnection:
            return [NSString stringWithFormat:@"%@@localhost%@", ([connectionController user] && [[connectionController user] length])?[connectionController user]:@"anonymous", port];
            break;
        case SPTCPIPConnection:
            return [NSString stringWithFormat:@"%@@%@%@",
                    ([connectionController user] && [[connectionController user] length]) ? [connectionController user] : @"anonymous",
                    [connectionController host] ? [connectionController host] : @"",
                    port];
            break;
        case SPSSHTunnelConnection:
            return [NSString stringWithFormat:@"%@@%@%@&SSH&%@@%@:%@",
                    ([connectionController user] && [[connectionController user] length]) ? [connectionController user] : @"anonymous",
                    [connectionController host] ? [connectionController host] : @"", port,
                    ([connectionController sshUser] && [[connectionController sshUser] length]) ? [connectionController sshUser] : @"anonymous",
                    [connectionController sshHost] ? [connectionController sshHost] : @"",
                    ([[connectionController sshPort] length]) ? [connectionController sshPort] : @"22"];
    }

    return @"_";
}

/**
 * Returns the full window title which is mainly used for tab tooltips
 */

- (NSString *)tabTitleForTooltip
{
    NSMutableString *tabTitle;

    // Determine name details
    NSString *pathName = @"";
    if ([[[self fileURL] path] length] && ![self isUntitled]) {
        pathName = [NSString stringWithFormat:@"%@ — ", [[[self fileURL] path] lastPathComponent]];
    }

    if ([connectionController isConnecting]) {
        return NSLocalizedString(@"Connecting…", @"window title string indicating that sp is connecting");
    }

    if ([self getConnection] == nil) return [NSString stringWithFormat:@"%@%@", pathName, [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleNameKey]];

    tabTitle = [NSMutableString string];

    // Add the MySQL version to the window title if enabled in prefs
    if ([prefs boolForKey:SPDisplayServerVersionInWindowTitle]) [tabTitle appendFormat:@"(MySQL %@)\n", [self mySQLVersion]];

    [tabTitle appendString:[self name]];
    if ([self database]) {
        if ([tabTitle length]) [tabTitle appendString:@"/"];
        [tabTitle appendString:[self database]];
    }
    if ([[self table] length]) {
        if ([tabTitle length]) [tabTitle appendString:@"/"];
        [tabTitle appendString:[self table]];
    }
    return tabTitle;
}

/**
 * Returns the currently selected database
 */
- (NSString *)database
{
    return selectedDatabase;
}

/**
 * Returns the MySQL version
 */
- (NSString *)mySQLVersion
{
    return mySQLVersion;
}

/**
 * Returns the current user
 */
- (NSString *)user
{
    NSString *theUser = [connectionController user];
    if (!theUser) theUser = @"";
    return theUser;
}

/**
 * Returns the current host's port
 */
- (NSString *)port
{
    NSString *thePort = [connectionController port];
    if (!thePort) return @"";
    return thePort;
}

- (BOOL)isSaveInBundle
{
    return _isSavedInBundle;
}

- (NSArray *)allTableNames
{
    return [tablesListInstance allTableNames];
}

- (SPCreateDatabaseInfo *)createDatabaseInfo
{
    SPCreateDatabaseInfo *dbInfo = [[SPCreateDatabaseInfo alloc] init];

    [dbInfo setDatabaseName:[self database]];
    [dbInfo setDefaultEncoding:[databaseDataInstance getDatabaseDefaultCharacterSet]];
    [dbInfo setDefaultCollation:[databaseDataInstance getDatabaseDefaultCollation]];

    return dbInfo;
}

/**
 * Retrieve the view that is currently selected from the database
 *
 * MUST BE CALLED ON THE UI THREAD!
 */
- (SPTableViewType)currentlySelectedView
{
    SPTableViewType theView = NSNotFound;

    // -selectedTabViewItem is a UI method according to Xcode 9.2!
    // jamesstout note - this is called a LOT.
    // using tableViewTypeEnumFromString is 5-7x faster than if/else isEqualToString:
    NSString *viewName = [[[tableTabView onMainThread] selectedTabViewItem] identifier];

    SPTableViewType enumValue = [viewName tableViewTypeEnumFromString];

    switch (enumValue) {
        case SPTableViewStructure:
            theView = SPTableViewStructure;
            break;
        case SPTableViewContent:
            theView = SPTableViewContent;
            break;
        case SPTableViewCustomQuery:
            theView = SPTableViewCustomQuery;
            break;
        case SPTableViewStatus:
            theView = SPTableViewStatus;
            break;
        case SPTableViewRelations:
            theView = SPTableViewRelations;
            break;
        case SPTableViewTriggers:
            theView = SPTableViewTriggers;
            break;
        default:
            theView = SPTableViewInvalid;
    }

    return theView;
}

#pragma mark -
#pragma mark Notification center methods

/**
 * Invoked before a query is performed
 */
- (void)willPerformQuery:(NSNotification *)notification
{
    [self setIsProcessing:YES];
    [queryProgressBar startAnimation:self];
}

/**
 * Invoked after a query has been performed
 */
- (void)hasPerformedQuery:(NSNotification *)notification
{
    [self setIsProcessing:NO];
    [queryProgressBar stopAnimation:self];
}

/**
 * Invoked when the application will terminate
 */
- (void)applicationWillTerminate:(NSNotification *)notification
{

    SPLog(@"applicationWillTerminate");
    appIsTerminating = YES;
    // Auto-save preferences to spf file based connection
    if([self fileURL] && [[[self fileURL] path] length] && ![self isUntitled]) {
        if (_isConnected && ![self saveDocumentWithFilePath:nil inBackground:YES onlyPreferences:YES contextInfo:nil]) {
            NSLog(@"Preference data for file ‘%@’ could not be saved.", [[self fileURL] path]);
            NSBeep();
        }
    }

    [tablesListInstance selectionShouldChangeInTableView:nil];

    // Note that this call does not need to be removed in release builds as leaks analysis output is only
    // dumped if [[SPLogger logger] setDumpLeaksOnTermination]; has been called first.
    [[SPLogger logger] dumpLeaks];
}

#pragma mark -
#pragma mark Menu methods

/**
 * Saves SP session or if Custom Query tab is active the editor's content as SQL file
 * If sender == nil then the call came from [self writeSafelyToURL:ofType:forSaveOperation:error]
 */
- (IBAction)saveConnectionSheet:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    NSString *filename;
    NSString *contextInfo;

    [panel setAllowsOtherFileTypes:NO];
    [panel setCanSelectHiddenExtension:YES];

    // Save Query...
    if (sender != nil && [sender tag] == SPMainMenuFileSaveQuery) {

        // If Save was invoked, check whether the file was previously opened, and if so save without the panel
        if ([sender tag] == SPMainMenuFileSaveQuery && [[[self sqlFileURL] path] length]) {
            NSError *error = nil;
            NSString *content = [NSString stringWithString:[[[customQueryInstance valueForKeyPath:@"textView"] textStorage] string]];
            [content writeToURL:sqlFileURL atomically:YES encoding:sqlFileEncoding error:&error];
            return;
        }

        // Save the editor's content as SQL file
        [panel setAccessoryView:[SPEncodingPopupAccessory encodingAccessory:[prefs integerForKey:SPLastSQLFileEncoding]
                                                        includeDefaultEntry:NO
                                                              encodingPopUp:&encodingPopUp]];

        [panel setAllowedFileTypes:@[SPFileExtensionSQL]];

        if (![prefs stringForKey:@"lastSqlFileName"]) {
            [prefs setObject:@"" forKey:@"lastSqlFileName"];
        }

        filename = [prefs stringForKey:@"lastSqlFileName"];
        contextInfo = @"saveSQLfile";

        // If no lastSqlFileEncoding in prefs set it to UTF-8
        if (![prefs integerForKey:SPLastSQLFileEncoding]) {
            [prefs setInteger:4 forKey:SPLastSQLFileEncoding];
        }

        [encodingPopUp setEnabled:YES];
    }
    // Save Connection
    else if (sender == nil || [sender tag] == SPMainMenuFileSaveConnection) {

        // If Save was invoked check for fileURL and Untitled docs and save the spf file without save panel
        // otherwise ask for file name
        if (sender != nil && [sender tag] == SPMainMenuFileSaveConnection && [[[self fileURL] path] length] && ![self isUntitled]) {
            [self saveDocumentWithFilePath:nil inBackground:YES onlyPreferences:NO contextInfo:nil];
            return;
        }

        // Save current session (open connection windows as SPF file)
        [panel setAllowedFileTypes:@[SPFileExtensionDefault]];

        [self prepareSaveAccessoryViewWithPanel:panel];

        [self.saveConnectionIncludeQuery setEnabled:([[[[customQueryInstance valueForKeyPath:@"textView"] textStorage] string] length])];

        // Update accessory button states
        [self validateSaveConnectionAccessory:nil];

        // TODO note: it seems that one has problems with a NSSecureTextField inside an accessory view - ask HansJB
        [[self.saveConnectionEncryptString cell] setControlView:self.saveConnectionAccessory];
        [panel setAccessoryView:self.saveConnectionAccessory];

        // Set file name to the name of the connection
        filename = [self name];

        contextInfo = sender == nil ? @"saveSPFfileAndClose" : @"saveSPFfile";
    }
    // Save Session
    else if (sender == nil || [sender tag] == SPMainMenuFileSaveSession) {

        // Save current session (open connection windows as SPFS file)
        [panel setAllowedFileTypes:@[SPBundleFileExtension]];

        [self prepareSaveAccessoryViewWithPanel:panel];

        // Update accessory button states
        [self validateSaveConnectionAccessory:nil];
        [self.saveConnectionIncludeQuery setEnabled:YES];

        // TODO note: it seems that one has problems with a NSSecureTextField
        // inside an accessory view - ask HansJB
        [[self.saveConnectionEncryptString cell] setControlView:self.saveConnectionAccessory];
        [panel setAccessoryView:self.saveConnectionAccessory];

        // Set file name
        filename = [NSString stringWithFormat:NSLocalizedString(@"Session", @"Initial filename for 'Save session' file")];

        contextInfo = @"saveSession";
    }
    else {
        return;
    }

    [panel setNameFieldStringValue:filename];

    [panel beginSheetModalForWindow:[self.parentWindowController window] completionHandler:^(NSInteger returnCode) {
        [self saveConnectionPanelDidEnd:panel returnCode:returnCode contextInfo:contextInfo];
    }];
}
/**
 * Control the save connection panel's accessory view
 */
- (IBAction)validateSaveConnectionAccessory:(id)sender
{
    // [saveConnectionAutoConnect setEnabled:([saveConnectionSavePassword state] == NSControlStateValueOn)];
    [self.saveConnectionSavePasswordAlert setHidden:([self.saveConnectionSavePassword state] == NSControlStateValueOff)];

    // If user checks the Encrypt check box set focus to password field
    if (sender == self.saveConnectionEncrypt && [self.saveConnectionEncrypt state] == NSControlStateValueOn) [self.saveConnectionEncryptString selectText:sender];

    // Unfocus saveConnectionEncryptString
    if (sender == self.saveConnectionEncrypt && [self.saveConnectionEncrypt state] == NSControlStateValueOff) {
        // [saveConnectionEncryptString setStringValue:[saveConnectionEncryptString stringValue]];
        // TODO how can one make it better ?
        [[self.saveConnectionEncryptString window] makeFirstResponder:[[self.saveConnectionEncryptString window] initialFirstResponder]];
    }
}

- (void)saveConnectionPanelDidEnd:(NSSavePanel *)panel returnCode:(NSInteger)returnCode contextInfo:(NSString *)contextInfo
{
    [panel orderOut:nil]; // by default OS X hides the panel only after the current method is done

    if (returnCode == NSModalResponseOK) {

        NSString *fileName = [[panel URL] path];
        NSError *error = nil;

        // Save file as SQL file by using the chosen encoding
        if ([contextInfo isEqualToString:@"saveSQLfile"]) {

            [prefs setInteger:[[encodingPopUp selectedItem] tag] forKey:SPLastSQLFileEncoding];
            [prefs setObject:[fileName lastPathComponent] forKey:@"lastSqlFileName"];

            NSString *content = [NSString stringWithString:[[[customQueryInstance valueForKeyPath:@"textView"] textStorage] string]];
            [content writeToFile:fileName
                      atomically:YES
                        encoding:[[encodingPopUp selectedItem] tag]
                           error:&error];

            if (error != nil) {
                NSAlert *errorAlert = [NSAlert alertWithError:error];
                [errorAlert runModal];
            }
            [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:fileName]];

        // Save connection and session as SPF file
        } else if([contextInfo isEqualToString:@"saveSPFfile"] || [contextInfo isEqualToString:@"saveSPFfileAndClose"]) {
            // Save changes of saveConnectionEncryptString
            [[self.saveConnectionEncryptString window] makeFirstResponder:[[self.saveConnectionEncryptString window] initialFirstResponder]];

            [self saveDocumentWithFilePath:fileName inBackground:NO onlyPreferences:NO contextInfo:nil];

            if ([contextInfo isEqualToString:@"saveSPFfileAndClose"]) {
                [self closeAndDisconnect];
            }

        // Save all open windows including all tabs as session
        } else if ([contextInfo isEqualToString:@"saveSession"]) {
            NSDictionary *userInfo = @{
                @"contextInfo": contextInfo,
                @"encrypted": [NSNumber numberWithBool:[self.saveConnectionEncrypt state] == NSControlStateValueOn],
                @"saveConnectionEncryptString": [self.saveConnectionEncryptString stringValue],
                @"auto_connect": [NSNumber numberWithBool:[self.saveConnectionAutoConnect state] == NSControlStateValueOn],
                @"save_password": [NSNumber numberWithBool:[self.saveConnectionSavePassword state] == NSControlStateValueOn],
                @"include_session": [NSNumber numberWithBool:[self.saveConnectionIncludeData state] == NSControlStateValueOn],
                @"save_editor_content": [NSNumber numberWithBool:[self.saveConnectionIncludeQuery state] == NSControlStateValueOn]
            };
            [[NSNotificationCenter defaultCenter] postNotificationName:SPDocumentSaveToSPFNotification object:fileName userInfo:userInfo];
        }
    }
}

- (BOOL)saveDocumentWithFilePath:(NSString *)fileName inBackground:(BOOL)saveInBackground onlyPreferences:(BOOL)saveOnlyPreferences contextInfo:(NSDictionary*)contextInfo
{
    // Do not save if no connection is/was available
    if (saveInBackground && ([self mySQLVersion] == nil || ![[self mySQLVersion] length])) return NO;

    NSMutableDictionary *spfDocData_temp = [NSMutableDictionary dictionary];

    if (fileName == nil) fileName = [[self fileURL] path];

    // Store save panel settings or take them from spfDocData
    if (!saveInBackground && contextInfo == nil) {
        [spfDocData_temp setObject:[NSNumber numberWithBool:([self.saveConnectionEncrypt state]==NSControlStateValueOn) ? YES : NO ] forKey:@"encrypted"];
        if([[spfDocData_temp objectForKey:@"encrypted"] boolValue]) {
            [spfDocData_temp setObject:[self.saveConnectionEncryptString stringValue] forKey:@"e_string"];
        }
        [spfDocData_temp setObject:[NSNumber numberWithBool:([self.saveConnectionAutoConnect state]==NSControlStateValueOn) ? YES : NO ] forKey:@"auto_connect"];
        [spfDocData_temp setObject:[NSNumber numberWithBool:([self.saveConnectionSavePassword state]==NSControlStateValueOn) ? YES : NO ] forKey:@"save_password"];
        [spfDocData_temp setObject:[NSNumber numberWithBool:([self.saveConnectionIncludeData state]==NSControlStateValueOn) ? YES : NO ] forKey:@"include_session"];
        [spfDocData_temp setObject:@NO forKey:@"save_editor_content"];
        if([[[[customQueryInstance valueForKeyPath:@"textView"] textStorage] string] length]) {
            [spfDocData_temp setObject:[NSNumber numberWithBool:([self.saveConnectionIncludeQuery state] == NSControlStateValueOn) ? YES : NO] forKey:@"save_editor_content"];
        }
    }
    else {
        // If contextInfo != nil call came from other SPDatabaseDocument while saving it as bundle
        [spfDocData_temp addEntriesFromDictionary:(contextInfo == nil ? spfDocData : contextInfo)];
    }

    // Update only query favourites, history, etc. by reading the file again
    if (saveOnlyPreferences) {

        // Check URL for safety reasons
        if (![[[self fileURL] path] length] || [self isUntitled]) {
            NSLog(@"Couldn't save data. No file URL found!");
            NSBeep();
            return NO;
        }

        NSMutableDictionary *spf = [[NSMutableDictionary alloc] init];
        {
            NSError *error = nil;

            NSData *pData = [NSData dataWithContentsOfFile:fileName options:NSUncachedRead error:&error];

            if (pData && !error) {
                NSDictionary *pDict = [NSPropertyListSerialization propertyListWithData:pData
                                                                                options:NSPropertyListImmutable
                                                                                 format:NULL
                                                                                  error:&error];

                if (pDict && !error) {
                    [spf addEntriesFromDictionary:pDict];
                }
            }

            if(![spf count] || error) {
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:NSLocalizedString(@"Error while reading connection data file", @"error while reading connection data file")];
                [alert setInformativeText:[NSString stringWithFormat:NSLocalizedString(@"Connection data file “%@” couldn't be read. Please try to save the document under a different name.\n\nDetails: %@", @"message error while reading connection data file and suggesting to save it under a differnet name"), [fileName lastPathComponent], [error localizedDescription]]];

                // Order of buttons matters! first button has "firstButtonReturn" return value from runModal()
                [alert addButtonWithTitle:NSLocalizedString(@"OK", @"OK button")];
                [alert addButtonWithTitle:NSLocalizedString(@"Ignore", @"ignore button")];

                return [alert runModal] == NSAlertSecondButtonReturn;
            }
        }

        // For dispatching later
        if (![[spf objectForKey:SPFFormatKey] isEqualToString:SPFConnectionContentType]) {
            NSLog(@"SPF file format is not 'connection'.");
            return NO;
        }

        // Update the keys
        [spf setObject:[[SPQueryController sharedQueryController] favoritesForFileURL:[self fileURL]] forKey:SPQueryFavorites];
        // DON'T SAVE QUERY HISTORY IN EXPORTS FOR SECURITY
        // [spfStructure setObject:[stateDetails objectForKey:SPQueryHistory] forKey:SPQueryHistory];
        [spf setObject:[[SPQueryController sharedQueryController] contentFilterForFileURL:[self fileURL]] forKey:SPContentFilters];

        // Save it again
        NSError *error = nil;
        NSData *plist = [NSPropertyListSerialization dataWithPropertyList:spf
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                                  options:0
                                                                    error:&error];

        if (error) {
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error while converting connection data", @"error while converting connection data") message:[error localizedDescription] callback:nil];
            return NO;
        }

        [plist writeToFile:fileName options:NSAtomicWrite error:&error];

        if (error != nil) {
            NSAlert *errorAlert = [NSAlert alertWithError:error];
            [errorAlert runModal];
            return NO;
        }

        [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:fileName]];

        return YES;
    }

    // Set up the dictionary to save to file, together with a data store
    NSMutableDictionary *spfStructure = [NSMutableDictionary dictionary];
    NSMutableDictionary *spfData = [NSMutableDictionary dictionary];

    // Add basic details
    [spfStructure setObject:@1 forKey:SPFVersionKey];
    [spfStructure setObject:SPFConnectionContentType forKey:SPFFormatKey];
    [spfStructure setObject:@"mysql" forKey:@"rdbms_type"];
    if([self mySQLVersion]) [spfStructure setObject:[self mySQLVersion] forKey:@"rdbms_version"];

    // Add auto-connect if appropriate
    [spfStructure setObject:[spfDocData_temp objectForKey:@"auto_connect"] forKey:@"auto_connect"];

    // Set up the document details to store
    NSMutableDictionary *stateDetailsToSave = [NSMutableDictionary dictionaryWithDictionary:@{
        @"connection": @YES,
        @"history":    @YES,
    }];

    // Include session data like selected table, view etc. ?
    if ([[spfDocData_temp objectForKey:@"include_session"] boolValue]) [stateDetailsToSave setObject:@YES forKey:@"session"];

    // Include the query editor contents if asked to
    if ([[spfDocData_temp objectForKey:@"save_editor_content"] boolValue]) {
        [stateDetailsToSave setObject:@YES forKey:@"query"];
        [stateDetailsToSave setObject:@YES forKey:@"enablecompression"];
    }

    // Add passwords if asked to
    if ([[spfDocData_temp objectForKey:@"save_password"] boolValue]) [stateDetailsToSave setObject:@YES forKey:@"password"];

    // Retrieve details and add to the appropriate dictionaries
    NSMutableDictionary *stateDetails = [NSMutableDictionary dictionaryWithDictionary:[self stateIncludingDetails:stateDetailsToSave]];
    [spfStructure setObject:[stateDetails objectForKey:SPQueryFavorites] forKey:SPQueryFavorites];
    // DON'T SAVE QUERY HISTORY IN EXPORTS FOR SECURITY
    // [spfStructure setObject:[stateDetails objectForKey:SPQueryHistory] forKey:SPQueryHistory];
    [spfStructure setObject:[stateDetails objectForKey:SPContentFilters] forKey:SPContentFilters];
    [stateDetails removeObjectsForKeys:@[SPQueryFavorites, SPQueryHistory, SPContentFilters]];
    [spfData addEntriesFromDictionary:stateDetails];

    // Determine whether to use encryption when adding the data
    [spfStructure setObject:[spfDocData_temp objectForKey:@"encrypted"] forKey:@"encrypted"];

    if (![[spfDocData_temp objectForKey:@"encrypted"] boolValue]) {

        // Convert the content selection to encoded data
        if ([[spfData objectForKey:@"session"] objectForKey:@"contentSelection"]) {
            NSMutableDictionary *sessionInfo = [NSMutableDictionary dictionaryWithDictionary:[spfData objectForKey:@"session"]];
            NSMutableData *dataToEncode = [[NSMutableData alloc] init];
            NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:dataToEncode];
            [archiver encodeObject:[sessionInfo objectForKey:@"contentSelection"] forKey:@"data"];
            [archiver finishEncoding];
            [sessionInfo setObject:dataToEncode forKey:@"contentSelection"];
            [spfData setObject:sessionInfo forKey:@"session"];
        }

        [spfStructure setObject:spfData forKey:@"data"];
    }
    else {
        NSMutableData *dataToEncrypt = [[NSMutableData alloc] init];
        NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:dataToEncrypt];
        [archiver encodeObject:spfData forKey:@"data"];
        [archiver finishEncoding];
        [spfStructure setObject:[dataToEncrypt dataEncryptedWithPassword:[spfDocData_temp objectForKey:@"e_string"]] forKey:@"data"];
    }

    // Convert to plist
    NSError *error = nil;
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:spfStructure
                                                               format:NSPropertyListXMLFormat_v1_0
                                                              options:0
                                                                error:&error];

    if (error) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error while converting connection data", @"error while converting connection data") message:[error localizedDescription] callback:nil];
        return NO;
    }

    [plist writeToFile:fileName options:NSAtomicWrite error:&error];

    if (error != nil){
        NSAlert *errorAlert = [NSAlert alertWithError:error];
        [errorAlert runModal];
        return NO;
    }

    if (contextInfo == nil) {
        // Register and update query favorites, content filter, and history for the (new) file URL
        NSMutableDictionary *preferences = [[NSMutableDictionary alloc] init];
        if([spfStructure objectForKey:SPQueryHistory]){
            [preferences setObject:[spfStructure objectForKey:SPQueryHistory] forKey:SPQueryHistory];
        }
        if([spfStructure objectForKey:SPQueryFavorites]){
            [preferences setObject:[spfStructure objectForKey:SPQueryFavorites] forKey:SPQueryFavorites];
        }
        if([spfStructure objectForKey:SPContentFilters]){
            [preferences setObject:[spfStructure objectForKey:SPContentFilters] forKey:SPContentFilters];
        }
        [[SPQueryController sharedQueryController] registerDocumentWithFileURL:[NSURL fileURLWithPath:fileName] andContextInfo:preferences];

        NSURL *newURL = [NSURL fileURLWithPath:fileName];
        [self setFileURL:newURL];
        [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:fileName]];

        [self updateWindowTitle:self];

        // Store doc data permanently
        [spfDocData removeAllObjects];
        [spfDocData addEntriesFromDictionary:spfDocData_temp];
    }

    return YES;
}

/**
 * Open the currently selected database in a new tab, clearing any table selection.
 */
- (void)openDatabaseInNewTab {

    // Get the current state
    NSDictionary *allStateDetails = @{
        @"connection" : @YES,
        @"history"    : @YES,
        @"session"    : @YES,
        @"query"      : @YES,
        @"password"   : @YES
    };
    NSMutableDictionary *currentState = [NSMutableDictionary dictionaryWithDictionary:[self stateIncludingDetails:allStateDetails]];

    // Ensure it's set to autoconnect, and clear the table
    [currentState setObject:@YES forKey:@"auto_connect"];
    NSMutableDictionary *sessionDict = [NSMutableDictionary dictionaryWithDictionary:[currentState objectForKey:@"session"]];
    [sessionDict removeObjectForKey:@"table"];
    [currentState setObject:sessionDict forKey:@"session"];

    [[NSNotificationCenter defaultCenter] postNotificationName:SPDocumentDuplicateTabNotification object:nil userInfo:currentState];
}

/**
 * Passes the request to the dataImport object
 */
- (void)importFile {
    [tableDumpInstance importFile];
}

/**
 * Passes the request to the dataImport object
 */
- (void)importFromClipboard {
    [tableDumpInstance importFromClipboard];
}

/**
 * Show the MySQL Help TOC of the current MySQL connection
 * Invoked by the MainMenu > Help > MySQL Help
 */
- (void)showMySQLHelp {
    [helpViewerClientInstance showHelpFor:SPHelpViewerSearchTOC addToHistory:YES calledByAutoHelp:NO];
    [[helpViewerClientInstance helpWebViewWindow] makeKeyWindow];
}

/**
 * Forwards a responder request to set the focus to the table list filter area or table list
 */
- (IBAction) makeTableListFilterHaveFocus:(id)sender
{
    [tablesListInstance performSelector:@selector(makeTableListFilterHaveFocus) withObject:nil afterDelay:0.1];
}


- (IBAction)showConnectionDebugMessages:(id)sender {

    SPConnectionController *conn = self.connectionController;

    NSString *debugMessages = [conn->sshTunnel debugMessages];

    SPLog(@"%@", debugMessages);

    conn->errorDetailWindow.title = NSLocalizedString(@"SSH Tunnel Debugging Info", @"SSH Tunnel Debugging Info");
    conn->errorDetailText.string = debugMessages;

    [[self parentWindowControllerWindow] beginSheet:conn->errorDetailWindow completionHandler:nil];

}

/**
 * Menu item validation.
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    SEL action = [menuItem action];

    if (action == @selector(chooseDatabase:)) {
        return _isConnected && databaseListIsSelectable;
    }

    if (!_isConnected || _isWorkingLevel) {
        return action == @selector(terminate:);
    }

    // Data export
    if (action == @selector(export:)) {
        return (([self database] != nil) && ([[tablesListInstance tables] count] > 1));
    }

    // Selected tables data export
    if (action == @selector(exportSelectedTablesAs:)) {

        NSInteger tag = [menuItem tag];
        NSInteger type = [tablesListInstance tableType];
        NSInteger numberOfSelectedItems = [[[tablesListInstance valueForKeyPath:@"tablesListView"] selectedRowIndexes] count];

        BOOL enable = (([self database] != nil) && numberOfSelectedItems);

        // Enable all export formats if at least one table/view is selected
        if (numberOfSelectedItems == 1) {
            if (type == SPTableTypeTable || type == SPTableTypeView) {
                return enable;
            }
            else if ((type == SPTableTypeProc) || (type == SPTableTypeFunc)) {
                return (enable && (tag == SPSQLExport));
            }
        }
        else {
            for (NSNumber *eachType in [tablesListInstance selectedTableTypes])
            {
                if ([eachType intValue] == SPTableTypeTable || [eachType intValue] == SPTableTypeView) return enable;
            }

            return (enable && (tag == SPSQLExport));
        }
    }

    // Can only be enabled on mysql 4.1+
    if (action == @selector(alterDatabase:)) {
        return (([self database] != nil));
    }

    // Table specific actions
    if (action == @selector(viewStructure) ||
        action == @selector(viewContent)   ||
        action == @selector(viewRelations) ||
        action == @selector(viewStatus)    ||
        action == @selector(viewTriggers))
    {
        return [self database] != nil && [[[tablesListInstance valueForKeyPath:@"tablesListView"] selectedRowIndexes] count];

    }

    // Database specific actions
    if (action == @selector(import:)               ||
        action == @selector(removeDatabase:)       ||
        action == @selector(copyDatabase:)         ||
        action == @selector(renameDatabase:)       ||
        action == @selector(openDatabaseInNewTab:) ||
        action == @selector(refreshTables:))
    {
        return [self database] != nil;
    }

    if (action == @selector(importFromClipboard:)){
        return [self database] && [[NSPasteboard generalPasteboard] availableTypeFromArray:@[NSPasteboardTypeString]];
    }

    // Change "Save Query/Queries" menu item title dynamically
    // and disable it if no query in the editor
    if (action == @selector(saveConnectionSheet:) && [menuItem tag] == 0) {
        if ([customQueryInstance numberOfQueries] < 1) {
            [menuItem setTitle:NSLocalizedString(@"Save Query…", @"Save Query…")];

            return NO;
        }
        else {
            [menuItem setTitle:[customQueryInstance numberOfQueries] == 1 ? NSLocalizedString(@"Save Query…", @"Save Query…") : NSLocalizedString(@"Save Queries…", @"Save Queries…")];
        }

        return YES;
    }

    if (action == @selector(printDocument:)) {
        return (
                ([self database] != nil && [[tablesListInstance valueForKeyPath:@"tablesListView"] numberOfSelectedRows] == 1) ||
                // If Custom Query Tab is active the textView will handle printDocument by itself
                // if it is first responder; otherwise allow to print the Query Result table even
                // if no db/table is selected
                [self currentlySelectedView] == SPTableViewCustomQuery
                );
    }

    if (action == @selector(chooseEncoding:)) {
        return [self supportsEncoding];
    }

    // unhide the debugging info menu
    if (action == @selector(showConnectionDebugMessages:)) {
        if(_isConnected && connectionController->sshTunnel != nil){
            menuItem.hidden = NO;
            [menuItem.menu.itemArray enumerateObjectsUsingBlock:^(NSMenuItem *item2, NSUInteger idx, BOOL * _Nonnull stop) {
                if ([item2.title isEqualToString:NSLocalizedString(@"SSH Tunnel Debugging Info", @"SSH Tunnel Debugging Info")]) {
                    SPLog(@"Unhiding HR above SSH Tunnel Debugging");
                    NSMenuItem *hrMenuItem = [menuItem.menu.itemArray safeObjectAtIndex:idx-1];
                    if(hrMenuItem.isSeparatorItem){
                        hrMenuItem.hidden = NO;
                    }
                    *stop = YES;
                }
            }];
        }
        return YES;
    }

    // Table actions and view switching
    if (action == @selector(analyzeTable:) ||
        action == @selector(optimizeTable:) ||
        action == @selector(repairTable:) ||
        action == @selector(flushTable:) ||
        action == @selector(checkTable:) ||
        action == @selector(checksumTable:) ||
        action == @selector(showCreateTableSyntax:) ||
        action == @selector(copyCreateTableSyntax:))
    {
        return [[[tablesListInstance valueForKeyPath:@"tablesListView"] selectedRowIndexes] count];
    }

    if (action == @selector(addConnectionToFavorites:)) {
        return ![connectionController selectedFavorite] || [connectionController isEditingConnection];
    }

    // Backward in history menu item
    if ((action == @selector(backForwardInHistory:)) && ([menuItem tag] == 0)) {
        return ([spHistoryControllerInstance countPrevious]);
    }

    // Forward in history menu item
    if ((action == @selector(backForwardInHistory:)) && ([menuItem tag] == 1)) {
        return [spHistoryControllerInstance countForward];
    }

    // Show/hide console
    if (action == @selector(toggleConsole:)) {
        [menuItem setTitle:([[[SPQueryController sharedQueryController] window] isVisible] && [[[NSApp keyWindow] windowController] isKindOfClass:[SPQueryController class]]) ? NSLocalizedString(@"Hide Console", @"hide console") : NSLocalizedString(@"Show Console", @"show console")];
        return YES;
    }

    // Clear console
    if (action == @selector(clearConsole:)) {
        return ([[SPQueryController sharedQueryController] consoleMessageCount] > 0);
    }

    // Show/hide console
    if (action == @selector(toggleNavigator:)) {
        [menuItem setTitle:([[[SPNavigatorController sharedNavigatorController] window] isVisible]) ? NSLocalizedString(@"Hide Navigator", @"hide navigator") : NSLocalizedString(@"Show Navigator", @"show navigator")];
    }

    // Focus on table content filter
    if (action == @selector(focusOnTableContentFilter:) || action == @selector(showFilterTable:)) {
        return ([self table] != nil && [[self table] isNotEqualTo:@""]);
    }

    // Focus on table list or filter resp.
    if (action == @selector(makeTableListFilterHaveFocus:)) {

        [menuItem setTitle:[[tablesListInstance valueForKeyPath:@"tables"] count] > 20 ? NSLocalizedString(@"Filter Tables", @"filter tables menu item") : NSLocalizedString(@"Change Focus to Table List", @"change focus to table list menu item")];

        return [[tablesListInstance valueForKeyPath:@"tables"] count] > 1;
    }

    // If validation for the sort favorites tableview items reaches here then the preferences window isn't
    // open return NO.
    if ((action == @selector(sortFavorites:)) || (action == @selector(reverseSortFavorites:))) {
        return NO;
    }

    // Default to YES for unhandled menus
    return YES;
}

/**
 * Adds the current database connection details to the user's favorites if it doesn't already exist.
 */
- (void)addConnectionToFavorites {
    // Obviously don't add if it already exists. We shouldn't really need this as the menu item validation
    // enables or disables the menu item based on the same method. Although to be safe do the check anyway
    // as we don't know what's calling this method.
    if ([connectionController selectedFavorite] && ![connectionController isEditingConnection]) {
        return;
    }

    // Request the connection controller to add its details to favorites
    [connectionController addFavoriteUsingCurrentDetails:self];
}

/**
 * Return YES if Custom Query is active.
 */
- (BOOL)isCustomQuerySelected
{
    return [[self selectedToolbarItemIdentifier] isEqualToString:SPMainToolbarCustomQuery];
}

/**
 * Return the createTableSyntaxWindow
 */
- (NSWindow *)getCreateTableSyntaxWindow
{
    return createTableSyntaxWindow;
}

#pragma mark -
#pragma mark Titlebar Methods

/**
 * Update the window title.
 */
- (void)updateWindowTitle:(id)sender {
    // Ensure a call on the main thread
    if (![NSThread isMainThread]) {
        return [[self onMainThread] updateWindowTitle:sender];
    }

    // Determine name details
    NSString *pathName = @"";
    if ([[[self fileURL] path] length] && ![self isUntitled]) {
        pathName = [NSString stringWithFormat:@"%@ — ", [[[self fileURL] path] lastPathComponent]];
    }

    if ([connectionController isConnecting]) {
        NSString *title = NSLocalizedString(@"Connecting…", @"window title string indicating that sp is connecting");
        [self.parentWindowController updateWindowWithTitle:title tabTitle:title];
    } else if (!_isConnected) {
        NSString *title = [NSString stringWithFormat:@"%@%@", pathName, [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleNameKey]];
        [self.parentWindowController updateWindowWithTitle:title tabTitle:title];
    } else {
        NSMutableString *windowTitle = [NSMutableString string];

        // Add the path to the window title
        [windowTitle appendString:pathName];

        // Add the MySQL version to the window title if enabled in prefs
        if ([prefs boolForKey:SPDisplayServerVersionInWindowTitle]) {
            [windowTitle appendFormat:@"(MySQL %@) ", mySQLVersion];
        }

        NSMutableString *tabTitle = [NSMutableString string];

        // Add the name to the window
        [windowTitle appendString:[self name]];
        [tabTitle appendString:[self name]];

        // If a database is selected, add to the window - and other tabs if host is the same but db different or table is not set
        if ([self database]) {
            [windowTitle appendFormat:@"/%@", [self database]];
            [tabTitle appendFormat:@"/%@", [self database]];
        }

        // Add the table name if one is selected
        if ([[self table] length]) {
            [windowTitle appendFormat:@"/%@", [self table]];
            [tabTitle appendFormat:@"/%@", [self table]];
        }
        [self.parentWindowController updateWindowWithTitle:windowTitle tabTitle:tabTitle];
        [self.parentWindowController updateWindowAccessoryWithColor:[[SPFavoriteColorSupport sharedInstance] colorForIndex:[connectionController colorIndex]] isSSL:[self.connectionController isConnectedViaSSL]];
    }
}

#pragma mark -
#pragma mark Toolbar Methods

/**
 * Return the identifier for the currently selected toolbar item, or nil if none is selected.
 */
- (NSString *)selectedToolbarItemIdentifier
{
    return [self.mainToolbar selectedItemIdentifier];
}

/**
 * toolbar delegate method
 */
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)willBeInsertedIntoToolbar {
    NSToolbarItem *toolbarItem = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];

    if ([itemIdentifier isEqualToString:SPMainToolbarDatabaseSelection]) {
        [toolbarItem setLabel:NSLocalizedString(@"Select Database", @"toolbar item for selecting a db")];
        [toolbarItem setPaletteLabel:[toolbarItem label]];
        [toolbarItem setView:chooseDatabaseButton];
        [chooseDatabaseButton setTarget:self];
        [chooseDatabaseButton setAction:@selector(chooseDatabase:)];
        [chooseDatabaseButton setEnabled:(_isConnected && !_isWorkingLevel)];

    } else if ([itemIdentifier isEqualToString:SPMainToolbarHistoryNavigation]) {
        [toolbarItem setLabel:NSLocalizedString(@"Table History", @"toolbar item for navigation history")];
        [toolbarItem setPaletteLabel:[toolbarItem label]];
        // At some point after 10.9 the sizing of NSSegmentedControl changed, resulting in clipping in newer OS X versions.
        // We can't just adjust the XIB, because then it would be wrong for older versions (possibly resulting in drawing artifacts),
        // so we have the OS determine the proper size at runtime.
        [historyControl sizeToFit];
        [toolbarItem setView:historyControl];

    } else if ([itemIdentifier isEqualToString:SPMainToolbarShowConsole]) {
        [toolbarItem setPaletteLabel:NSLocalizedString(@"Show Console", @"show console")];
        [toolbarItem setToolTip:NSLocalizedString(@"Show the console which shows all MySQL commands performed by Sequel Ace", @"tooltip for toolbar item for show console")];

        [toolbarItem setLabel:NSLocalizedString(@"Console", @"Console")];
        if (@available(macOS 11.0, *)) {
            [toolbarItem setImage:textAndCommandMacwindowImage];
        } else {
            [toolbarItem setImage:hideConsoleImage];
        }

        //set up the target action
        [toolbarItem setTarget:self];
        [toolbarItem setAction:@selector(showConsole)];

    } else if ([itemIdentifier isEqualToString:SPMainToolbarClearConsole]) {
        //set the text label to be displayed in the toolbar and customization palette
        [toolbarItem setLabel:NSLocalizedString(@"Clear Console", @"toolbar item for clear console")];
        [toolbarItem setPaletteLabel:NSLocalizedString(@"Clear Console", @"toolbar item for clear console")];
        //set up tooltip and image
        [toolbarItem setToolTip:NSLocalizedString(@"Clear the console which shows all MySQL commands performed by Sequel Ace", @"tooltip for toolbar item for clear console")];
        if (@available(macOS 11.0, *)) {
            [toolbarItem setImage:textAndCommandMacwindowImage];
        } else {
            [toolbarItem setImage:[NSImage imageNamed:@"clearconsole"]];
        }
        //set up the target action
        [toolbarItem setTarget:self];
        [toolbarItem setAction:@selector(clearConsole:)];

    } else if ([itemIdentifier isEqualToString:SPMainToolbarTableStructure]) {
        [toolbarItem setLabel:NSLocalizedString(@"Structure", @"toolbar item label for switching to the Table Structure tab")];
        [toolbarItem setPaletteLabel:NSLocalizedString(@"Edit Table Structure", @"toolbar item label for switching to the Table Structure tab")];
        //set up tooltip and image
        [toolbarItem setToolTip:NSLocalizedString(@"Switch to the Table Structure tab", @"tooltip for toolbar item for switching to the Table Structure tab")];
        if (@available(macOS 11.0, *)) {
            [toolbarItem setImage:[NSImage imageWithSystemSymbolName:@"scale.3d" accessibilityDescription:nil]];
        } else {
            [toolbarItem setImage:[NSImage imageNamed:@"toolbar-switch-to-structure"]];
        }
        //set up the target action
        [toolbarItem setTarget:self];
        [toolbarItem setAction:@selector(viewStructure)];

    } else if ([itemIdentifier isEqualToString:SPMainToolbarTableContent]) {
        [toolbarItem setLabel:NSLocalizedString(@"Content", @"toolbar item label for switching to the Table Content tab")];
        [toolbarItem setPaletteLabel:NSLocalizedString(@"Browse & Edit Table Content", @"toolbar item label for switching to the Table Content tab")];
        //set up tooltip and image
        [toolbarItem setToolTip:NSLocalizedString(@"Switch to the Table Content tab", @"tooltip for toolbar item for switching to the Table Content tab")];
        if (@available(macOS 11.0, *)) {
            [toolbarItem setImage:[NSImage imageWithSystemSymbolName:@"text.justify" accessibilityDescription:nil]];
        } else {
            [toolbarItem setImage:[NSImage imageNamed:@"toolbar-switch-to-browse"]];
        }
        //set up the target action
        [toolbarItem setTarget:self];
        [toolbarItem setAction:@selector(viewContent)];

    } else if ([itemIdentifier isEqualToString:SPMainToolbarCustomQuery]) {
        [toolbarItem setLabel:NSLocalizedString(@"Query", @"toolbar item label for switching to the Run Query tab")];
        [toolbarItem setPaletteLabel:NSLocalizedString(@"Run Custom Query", @"toolbar item label for switching to the Run Query tab")];
        //set up tooltip and image
        [toolbarItem setToolTip:NSLocalizedString(@"Switch to the Run Query tab", @"tooltip for toolbar item for switching to the Run Query tab")];
        if (@available(macOS 11.0, *)) {
            [toolbarItem setImage:[NSImage imageWithSystemSymbolName:@"terminal" accessibilityDescription:nil]];
        } else {
            [toolbarItem setImage:[NSImage imageNamed:@"toolbar-switch-to-sql"]];
        }
        //set up the target action
        [toolbarItem setTarget:self];
        [toolbarItem setAction:@selector(viewQuery)];

    } else if ([itemIdentifier isEqualToString:SPMainToolbarTableInfo]) {
        [toolbarItem setLabel:NSLocalizedString(@"Table Info", @"toolbar item label for switching to the Table Info tab")];
        [toolbarItem setPaletteLabel:NSLocalizedString(@"Table Info", @"toolbar item label for switching to the Table Info tab")];
        //set up tooltip and image
        [toolbarItem setToolTip:NSLocalizedString(@"Switch to the Table Info tab", @"tooltip for toolbar item for switching to the Table Info tab")];
        if (@available(macOS 11.0, *)) {
            [toolbarItem setImage:[NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:nil]];
        } else {
            [toolbarItem setImage:[NSImage imageNamed:NSImageNameInfo]];
        }
        //set up the target action
        [toolbarItem setTarget:self];
        [toolbarItem setAction:@selector(viewStatus)];

    } else if ([itemIdentifier isEqualToString:SPMainToolbarTableRelations]) {
        [toolbarItem setLabel:NSLocalizedString(@"Relations", @"toolbar item label for switching to the Table Relations tab")];
        [toolbarItem setPaletteLabel:NSLocalizedString(@"Table Relations", @"toolbar item label for switching to the Table Relations tab")];
        //set up tooltip and image
        [toolbarItem setToolTip:NSLocalizedString(@"Switch to the Table Relations tab", @"tooltip for toolbar item for switching to the Table Relations tab")];
        if (@available(macOS 11.0, *)) {
            [toolbarItem setImage:[NSImage imageWithSystemSymbolName:@"arrow.2.squarepath" accessibilityDescription:nil]];
        } else {
            [toolbarItem setImage:[NSImage imageNamed:@"toolbar-switch-to-table-relations"]];
        }
        //set up the target action
        [toolbarItem setTarget:self];
        [toolbarItem setAction:@selector(viewRelations)];

    } else if ([itemIdentifier isEqualToString:SPMainToolbarTableTriggers]) {
        [toolbarItem setLabel:NSLocalizedString(@"Triggers", @"toolbar item label for switching to the Table Triggers tab")];
        [toolbarItem setPaletteLabel:NSLocalizedString(@"Table Triggers", @"toolbar item label for switching to the Table Triggers tab")];
        //set up tooltip and image
        [toolbarItem setToolTip:NSLocalizedString(@"Switch to the Table Triggers tab", @"tooltip for toolbar item for switching to the Table Triggers tab")];
        if (@available(macOS 11.0, *)) {
            [toolbarItem setImage:[NSImage imageWithSystemSymbolName:@"bolt.circle" accessibilityDescription:nil]];
        } else {
            [toolbarItem setImage:[NSImage imageNamed:@"toolbar-switch-to-table-triggers"]];
        }
        //set up the target action
        [toolbarItem setTarget:self];
        [toolbarItem setAction:@selector(viewTriggers)];

    } else if ([itemIdentifier isEqualToString:SPMainToolbarUserManager]) {
        [toolbarItem setLabel:NSLocalizedString(@"Users", @"toolbar item label for switching to the User Manager tab")];
        [toolbarItem setPaletteLabel:NSLocalizedString(@"Users", @"toolbar item label for switching to the User Manager tab")];
        //set up tooltip and image
        [toolbarItem setToolTip:NSLocalizedString(@"Switch to the User Manager tab", @"tooltip for toolbar item for switching to the User Manager tab")];
        if (@available(macOS 11.0, *)) {
            [toolbarItem setImage:[NSImage imageWithSystemSymbolName:@"person.3" accessibilityDescription:nil]];
        } else {
            [toolbarItem setImage:[NSImage imageNamed:NSImageNameUserGroup]];
        }
        //set up the target action
        [toolbarItem setTarget:self];
        [toolbarItem setAction:@selector(showUserManager)];

    } else {
        //itemIdentifier refered to a toolbar item that is not provided or supported by us or cocoa
        toolbarItem = nil;
    }

    return toolbarItem;
}

- (void)toolbarWillAddItem:(NSNotification *)notification
{
    NSToolbarItem *toAdd = [[notification userInfo] objectForKey:@"item"];

    if([[toAdd itemIdentifier] isEqualToString:SPMainToolbarDatabaseSelection]) {
        chooseDatabaseToolbarItem = toAdd;
    }
}

- (void)toolbarDidRemoveItem:(NSNotification *)notification
{
    NSToolbarItem *removed = [[notification userInfo] objectForKey:@"item"];

    if([[removed itemIdentifier] isEqualToString:SPMainToolbarDatabaseSelection]) {
        chooseDatabaseToolbarItem = nil;
    }
}

/**
 * toolbar delegate method
 */
- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar
{
    return @[
        SPMainToolbarDatabaseSelection,
        SPMainToolbarHistoryNavigation,
        SPMainToolbarShowConsole,
        SPMainToolbarClearConsole,
        SPMainToolbarTableStructure,
        SPMainToolbarTableContent,
        SPMainToolbarCustomQuery,
        SPMainToolbarTableInfo,
        SPMainToolbarTableRelations,
        SPMainToolbarTableTriggers,
        SPMainToolbarUserManager,
        NSToolbarCustomizeToolbarItemIdentifier,
        NSToolbarFlexibleSpaceItemIdentifier,
        NSToolbarSpaceItemIdentifier,
        NSToolbarSeparatorItemIdentifier
    ];
}

/**
 * toolbar delegate method
 */
- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar
{
    return @[
        SPMainToolbarDatabaseSelection,
        NSToolbarSpaceItemIdentifier,
        SPMainToolbarTableStructure,
        SPMainToolbarTableContent,
        SPMainToolbarTableRelations,
        SPMainToolbarTableTriggers,
        SPMainToolbarTableInfo,
        SPMainToolbarCustomQuery,
        NSToolbarSpaceItemIdentifier,
        SPMainToolbarHistoryNavigation,
        NSToolbarSpaceItemIdentifier,
        SPMainToolbarUserManager,
        SPMainToolbarShowConsole
    ];
}

/**
 * toolbar delegate method
 */
- (NSArray *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{
    return @[
        SPMainToolbarTableStructure,
        SPMainToolbarTableContent,
        SPMainToolbarCustomQuery,
        SPMainToolbarTableInfo,
        SPMainToolbarTableRelations,
        SPMainToolbarTableTriggers
    ];

}

/**
 * Validates the toolbar items - JCS NOTE: this is called loads!
 */
- (BOOL)validateToolbarItem:(NSToolbarItem *)toolbarItem
{
    if (!_isConnected || _isWorkingLevel) return NO;

    NSString *identifier = [toolbarItem itemIdentifier];

    // Show console item
    if ([identifier isEqualToString:SPMainToolbarShowConsole]) {
        NSWindow *queryWindow = [[SPQueryController sharedQueryController] window];

        if (@available(macOS 11.0, *)) {
            toolbarItem.image = textAndCommandMacwindowImage;
        } else {
            if ([queryWindow isVisible]) {
                toolbarItem.image = showConsoleImage;
            } else {
                toolbarItem.image = hideConsoleImage;
            }
        }

        if ([queryWindow isKeyWindow]) {
            return NO;
        } else {
            return YES;
        }
    }

    // Clear console item
    if ([identifier isEqualToString:SPMainToolbarClearConsole]) {
        return ([[SPQueryController sharedQueryController] consoleMessageCount] > 0);
    }

    if (![identifier isEqualToString:SPMainToolbarCustomQuery] && ![identifier isEqualToString:SPMainToolbarUserManager]) {
        return (([tablesListInstance tableType] == SPTableTypeTable) || ([tablesListInstance tableType] == SPTableTypeView));
    }

    return YES;
}

#pragma mark -
#pragma mark Tab methods

/**
 * Invoked to determine whether the parent tab is allowed to close
 */
- (BOOL)parentTabShouldClose {

    // If no connection is available, always return YES.  Covers initial setup and disconnections.
    if(!_isConnected) {
        return YES;
    }

    // If tasks are active, return NO to allow tasks to complete
    if (_isWorkingLevel) {
        return NO;
    }

    // If the table list considers itself to be working, return NO. This catches open alerts, and
    // edits in progress in various views.
    if (![tablesListInstance selectionShouldChangeInTableView:nil]) {
        return NO;
    }

    // Auto-save spf file based connection and return if the save was not successful
    if ([self fileURL] && [[[self fileURL] path] length] && ![self isUntitled]) {
        BOOL isSaved = [self saveDocumentWithFilePath:nil inBackground:YES onlyPreferences:YES contextInfo:nil];
        if (isSaved) {
            [[SPQueryController sharedQueryController] removeRegisteredDocumentWithFileURL:[self fileURL]];
        } else {
            return NO;
        }
    }

    // Terminate all running BASH commands
    for (NSDictionary* cmd in [self runningActivities]) {
        NSInteger pid = [[cmd objectForKey:@"pid"] integerValue];
        NSTask *killTask = [[NSTask alloc] init];
        [killTask setLaunchPath:@"/bin/sh"];
        [killTask setArguments:[NSArray arrayWithObjects:@"-c", [NSString stringWithFormat:@"kill -9 -%ld", (long)pid], nil]];
        [killTask launch];
        [killTask waitUntilExit];
    }

    [[SPNavigatorController sharedNavigatorController] performSelectorOnMainThread:@selector(removeConnection:) withObject:[self connectionID] waitUntilDone:YES];

    // Note that this call does not need to be removed in release builds as leaks analysis output is only
    // dumped if [[SPLogger logger] setDumpLeaksOnTermination]; has been called first.
    [[SPLogger logger] dumpLeaks];
    // Return YES by default
    return YES;
}

#pragma mark -
#pragma mark NSDocument compatibility

/**
 * Set the NSURL for a .spf file for this connection instance.
 */
- (void)setFileURL:(NSURL *)theURL
{
    spfFileURL = theURL;
    if ([self.parentWindowController databaseDocument] == self) {
        if (spfFileURL && [spfFileURL isFileURL]) {
            [[self.parentWindowController window] setRepresentedURL:spfFileURL];
        } else {
            [[self.parentWindowController window] setRepresentedURL:nil];
        }
    }
}

/**
 * Retrieve the NSURL for the .spf file for this connection instance (if any)
 */
- (NSURL *)fileURL
{
    return [spfFileURL copy];
}

/**
 * Invoked if user chose "Save" from 'Do you want save changes you made...' sheet
 * which is called automatically if [self isDocumentEdited] == YES and user wanted to close an Untitled doc.
 */
- (BOOL)writeSafelyToURL:(NSURL *)absoluteURL ofType:(NSString *)typeName forSaveOperation:(NSSaveOperationType)saveOperation error:(NSError **)outError
{
    if(saveOperation == NSSaveOperation) {
        // Dummy error to avoid crashes after Canceling the Save Panel
        if (outError) *outError = [NSError errorWithDomain:@"SP_DOMAIN" code:1000 userInfo:nil];
        [self saveConnectionSheet:nil];
        return NO;
    }
    return YES;
}

/**
 * Shows "save?" dialog when closing the document if the an Untitled doc has doc-based query favorites or content filters.
 */
- (BOOL)isDocumentEdited
{
    return (
            [self fileURL] && [[[self fileURL] path] length] && [self isUntitled] && ([[[SPQueryController sharedQueryController] favoritesForFileURL:[self fileURL]] count]
                                                                                      || [[[[SPQueryController sharedQueryController] contentFilterForFileURL:[self fileURL]] objectForKey:@"number"] count]
                                                                                      || [[[[SPQueryController sharedQueryController] contentFilterForFileURL:[self fileURL]] objectForKey:@"date"] count]
                                                                                      || [[[[SPQueryController sharedQueryController] contentFilterForFileURL:[self fileURL]] objectForKey:@"string"] count])
            );
}

/**
 * The window title for this document.
 */
- (NSString *)displayName
{
    if (!_isConnected) {
        return [NSString stringWithFormat:@"%@%@", ([[[self fileURL] path] length] && ![self isUntitled]) ? [NSString stringWithFormat:@"%@ — ",[[[self fileURL] path] lastPathComponent]] : @"", [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleNameKey]];
    }
    return [[[self fileURL] path] lastPathComponent];
}

- (NSUndoManager *)undoManager
{
    return undoManager;
}

#pragma mark -
#pragma mark State saving and setting

/**
 * Retrieve the current database document state for saving.  A supplied dictionary
 * determines the level of detail that is required, with the following optional keys:
 *  - connection: Connection settings (with keychain references where available) and database
 *  - password: Whether to include passwords in the returned connection details
 *  - session: Selected table and view, together with content view filter, sort, scroll position
 *  - history: query history, per-doc query favourites, and per-doc content filters
 *  - query: custom query editor content
 *    - enablecompression: large (>50k) custom query editor contents will be stored as compressed data
 * If none of these are supplied, nil will be returned.
 */
- (NSDictionary *) stateIncludingDetails:(NSDictionary *)detailsToReturn
{
    BOOL returnConnection = [[detailsToReturn objectForKey:@"connection"] boolValue];
    BOOL includePasswords = [[detailsToReturn objectForKey:@"password"] boolValue];
    BOOL returnSession    = [[detailsToReturn objectForKey:@"session"] boolValue];
    BOOL returnHistory    = [[detailsToReturn objectForKey:@"history"] boolValue];
    BOOL returnQuery      = [[detailsToReturn objectForKey:@"query"] boolValue];

    if (!returnConnection && !returnSession && !returnHistory && !returnQuery) return nil;
    NSMutableDictionary *stateDetails = [NSMutableDictionary dictionary];

    // Add connection details
    if (returnConnection) {
        NSMutableDictionary *connection = [NSMutableDictionary dictionary];

        [connection setObject:@"mysql" forKey:@"rdbms_type"];

        NSString *connectionType;
        switch ([connectionController type]) {
            case SPTCPIPConnection:
                connectionType = @"SPTCPIPConnection";
                break;
            case SPSocketConnection:
                connectionType = @"SPSocketConnection";
                if ([connectionController socket] && [[connectionController socket] length]) [connection setObject:[connectionController socket] forKey:@"socket"];
                break;
            case SPSSHTunnelConnection:
                connectionType = @"SPSSHTunnelConnection";
                [connection setObject:[connectionController sshHost] forKey:@"ssh_host"];
                [connection setObject:[connectionController sshUser] forKey:@"ssh_user"];
                [connection setObject:[NSNumber numberWithInteger:[connectionController sshKeyLocationEnabled]] forKey:@"ssh_keyLocationEnabled"];
                if ([connectionController sshKeyLocation]) [connection setObject:[connectionController sshKeyLocation] forKey:@"ssh_keyLocation"];
                if ([connectionController sshPort] && [[connectionController sshPort] length]) [connection setObject:[NSNumber numberWithInteger:[[connectionController sshPort] integerValue]] forKey:@"ssh_port"];
                break;
            default:
                connectionType = @"SPTCPIPConnection";
        }
        [connection setObject:connectionType forKey:@"type"];

        NSString *kcid = [connectionController connectionKeychainID];
        if ([kcid length]) [connection setObject:kcid forKey:@"kcid"];
        [connection setObject:[self name] forKey:@"name"];
        [connection setObject:[self host] forKey:@"host"];
        [connection setObject:[self user] forKey:@"user"];
        if([connectionController colorIndex] >= 0)                              [connection setObject:[NSNumber numberWithInteger:[connectionController colorIndex]] forKey:SPFavoriteColorIndexKey];
        if([connectionController port] && [[connectionController port] length]) [connection setObject:[NSNumber numberWithInteger:[[connectionController port] integerValue]] forKey:@"port"];
        if([[self database] length])                                            [connection setObject:[self database] forKey:@"database"];

        if (includePasswords) {
            NSString *pw = [connectionController keychainPassword];
            if (!pw) pw = [connectionController password];
            if (pw) [connection setObject:pw forKey:@"password"];

            if ([connectionController type] == SPSSHTunnelConnection) {
                NSString *sshpw = [self keychainPasswordForSSHConnection:nil];
                if(![sshpw length]) sshpw = [connectionController sshPassword];
                [connection setObject:(sshpw ? sshpw : @"") forKey:@"ssh_password"];
            }
        }

        [connection setObject:[NSNumber numberWithInteger:[connectionController useSSL]] forKey:@"useSSL"];
        [connection setObject:[NSNumber numberWithInteger:[connectionController allowDataLocalInfile]] forKey:@"allowDataLocalInfile"];
        [connection setObject:[NSNumber numberWithInteger:[connectionController enableClearTextPlugin]] forKey:@"enableClearTextPlugin"];
        [connection setObject:[NSNumber numberWithInteger:[connectionController sslKeyFileLocationEnabled]] forKey:@"sslKeyFileLocationEnabled"];
        if ([connectionController sslKeyFileLocation]) [connection setObject:[connectionController sslKeyFileLocation] forKey:@"sslKeyFileLocation"];
        [connection setObject:[NSNumber numberWithInteger:[connectionController sslCertificateFileLocationEnabled]] forKey:@"sslCertificateFileLocationEnabled"];
        if ([connectionController sslCertificateFileLocation]) [connection setObject:[connectionController sslCertificateFileLocation] forKey:@"sslCertificateFileLocation"];
        [connection setObject:[NSNumber numberWithInteger:[connectionController sslCACertFileLocationEnabled]] forKey:@"sslCACertFileLocationEnabled"];
        if ([connectionController sslCACertFileLocation]) [connection setObject:[connectionController sslCACertFileLocation] forKey:@"sslCACertFileLocation"];

        [stateDetails setObject:[NSDictionary dictionaryWithDictionary:connection] forKey:@"connection"];
    }

    // Add document-specific saved settings
    if (returnHistory) {
        [stateDetails setObject:[[SPQueryController sharedQueryController] favoritesForFileURL:[self fileURL]] forKey:SPQueryFavorites];
        [stateDetails setObject:[[SPQueryController sharedQueryController] historyForFileURL:[self fileURL]] forKey:SPQueryHistory];
        [stateDetails setObject:[[SPQueryController sharedQueryController] contentFilterForFileURL:[self fileURL]] forKey:SPContentFilters];
    }

    // Set up a session state dictionary for either state or custom query
    NSMutableDictionary *sessionState = [NSMutableDictionary dictionary];

    // Store session state if appropriate
    if (returnSession) {

        if ([[self table] length]) [sessionState setObject:[self table] forKey:@"table"];

        NSString *currentlySelectedViewName;
        switch ([self currentlySelectedView]) {
            case SPTableViewStructure:
                currentlySelectedViewName = @"SP_VIEW_STRUCTURE";
                break;
            case SPTableViewContent:
                currentlySelectedViewName = @"SP_VIEW_CONTENT";
                break;
            case SPTableViewCustomQuery:
                currentlySelectedViewName = @"SP_VIEW_CUSTOMQUERY";
                break;
            case SPTableViewStatus:
                currentlySelectedViewName = @"SP_VIEW_STATUS";
                break;
            case SPTableViewRelations:
                currentlySelectedViewName = @"SP_VIEW_RELATIONS";
                break;
            case SPTableViewTriggers:
                currentlySelectedViewName = @"SP_VIEW_TRIGGERS";
                break;
            default:
                currentlySelectedViewName = @"SP_VIEW_STRUCTURE";
        }
        [sessionState setObject:currentlySelectedViewName forKey:@"view"];

        [sessionState setObject:[mySQLConnection encoding] forKey:@"connectionEncoding"];

        [sessionState setObject:[NSNumber numberWithBool:[[[self.parentWindowController window] toolbar] isVisible]] forKey:@"isToolbarVisible"];
        [sessionState setObject:[NSNumber numberWithFloat:[tableContentInstance tablesListWidth]] forKey:@"windowVerticalDividerPosition"];

        if ([tableContentInstance sortColumnName]) [sessionState setObject:[tableContentInstance sortColumnName] forKey:@"contentSortCol"];
        [sessionState setObject:[NSNumber numberWithBool:[tableContentInstance sortColumnIsAscending]] forKey:@"contentSortColIsAsc"];
        [sessionState setObject:[NSNumber numberWithInteger:[tableContentInstance pageNumber]] forKey:@"contentPageNumber"];
        [sessionState setObject:NSStringFromRect([tableContentInstance viewport]) forKey:@"contentViewport"];
        NSDictionary *filterSettings = [tableContentInstance filterSettings];
        if (filterSettings) [sessionState setObject:filterSettings forKey:@"contentFilterV2"];

        NSDictionary *contentSelectedRows = [tableContentInstance selectionDetailsAllowingIndexSelection:YES];
        if (contentSelectedRows) {
            [sessionState setObject:contentSelectedRows forKey:@"contentSelection"];
        }
    }

    // Add the custom query editor content if appropriate
    if (returnQuery) {
        NSString *queryString = [[[customQueryInstance valueForKeyPath:@"textView"] textStorage] string];
        if ([[detailsToReturn objectForKey:@"enablecompression"] boolValue] && [queryString length] > 50000) {
            [sessionState setObject:[[queryString dataUsingEncoding:NSUTF8StringEncoding] compress] forKey:@"queries"];
        } else {
            [sessionState setObject:queryString forKey:@"queries"];
        }
    }

    // Store the session state dictionary if either state or custom queries were saved
    if ([sessionState count]) [stateDetails setObject:[NSDictionary dictionaryWithDictionary:sessionState] forKey:@"session"];

    return stateDetails;
}

- (BOOL)setState:(NSDictionary *)stateDetails
{
    return [self setState:stateDetails fromFile:YES];
}

/**
 * Set the state of the document to the supplied dictionary, which should
 * at least contain a "connection" dictionary of details.
 * Returns whether the state was set successfully.
 */
- (BOOL)setState:(NSDictionary *)stateDetails fromFile:(BOOL)spfBased
{
    NSDictionary *connection = nil;
    NSInteger connectionType = -1;
    SPKeychain *keychain = nil;

    // If this document already has a connection, don't proceed.
    if (mySQLConnection) return NO;

    // Load the connection data from the state dictionary
    connection = [NSDictionary dictionaryWithDictionary:[stateDetails objectForKey:@"connection"]];
    if (!connection) return NO;

    if ([connection objectForKey:@"kcid"]) keychain = [[SPKeychain alloc] init];

    [self updateWindowTitle:self];

    if(spfBased) {
        // Deselect all favorites on the connection controller,
        // and clear and reset the connection state.
        [[connectionController favoritesOutlineView] deselectAll:connectionController];
        [connectionController updateFavoriteSelection:self];

        // Suppress the possibility to choose an other connection from the favorites
        // if a connection should initialized by SPF file. Otherwise it could happen
        // that the SPF file runs out of sync.
        [[connectionController favoritesOutlineView] setEnabled:NO];
    }
    else {
        [connectionController selectQuickConnectItem];
    }

    // Set the correct connection type
    NSString *typeString = [connection objectForKey:@"type"];
    if (typeString) {
        if ([typeString isEqualToString:@"SPTCPIPConnection"])          connectionType = SPTCPIPConnection;
        else if ([typeString isEqualToString:@"SPSocketConnection"])    connectionType = SPSocketConnection;
        else if ([typeString isEqualToString:@"SPSSHTunnelConnection"]) connectionType = SPSSHTunnelConnection;
        else                                                            connectionType = SPTCPIPConnection;

        [connectionController setType:connectionType];
        [connectionController resizeTabViewToConnectionType:connectionType animating:NO];
    }

    // Set basic details
    if ([connection objectForKey:@"name"])                 [connectionController setName:[connection objectForKey:@"name"]];
    if ([connection objectForKey:@"user"])                 [connectionController setUser:[connection objectForKey:@"user"]];
    if ([connection objectForKey:@"host"])                 [connectionController setHost:[connection objectForKey:@"host"]];
    if ([connection objectForKey:@"port"])                 [connectionController setPort:[NSString stringWithFormat:@"%ld", (long)[[connection objectForKey:@"port"] integerValue]]];
    if ([connection objectForKey:SPFavoriteColorIndexKey]) [connectionController setColorIndex:[(NSNumber *)[connection objectForKey:SPFavoriteColorIndexKey] integerValue]];


    //Set special connection settings
    if ([connection objectForKey:@"allowDataLocalInfile"])              [connectionController setAllowDataLocalInfile:[[connection objectForKey:@"allowDataLocalInfile"] intValue]];

    // Set Enable cleartext plugin
    if ([connection objectForKey:@"enableClearTextPlugin"])             [connectionController setEnableClearTextPlugin:[[connection objectForKey:@"enableClearTextPlugin"] intValue]];

    // Set SSL details
    if ([connection objectForKey:@"useSSL"])                            [connectionController setUseSSL:[[connection objectForKey:@"useSSL"] intValue]];
    if ([connection objectForKey:@"sslKeyFileLocationEnabled"])         [connectionController setSslKeyFileLocationEnabled:[[connection objectForKey:@"sslKeyFileLocationEnabled"] intValue]];
    if ([connection objectForKey:@"sslKeyFileLocation"])                [connectionController setSslKeyFileLocation:[connection objectForKey:@"sslKeyFileLocation"]];
    if ([connection objectForKey:@"sslCertificateFileLocationEnabled"]) [connectionController setSslCertificateFileLocationEnabled:[[connection objectForKey:@"sslCertificateFileLocationEnabled"] intValue]];
    if ([connection objectForKey:@"sslCertificateFileLocation"])        [connectionController setSslCertificateFileLocation:[connection objectForKey:@"sslCertificateFileLocation"]];
    if ([connection objectForKey:@"sslCACertFileLocationEnabled"])      [connectionController setSslCACertFileLocationEnabled:[[connection objectForKey:@"sslCACertFileLocationEnabled"] intValue]];
    if ([connection objectForKey:@"sslCACertFileLocation"])             [connectionController setSslCACertFileLocation:[connection objectForKey:@"sslCACertFileLocation"]];

    // Set the keychain details if available
    NSString *kcid = (NSString *)[connection objectForKey:@"kcid"];
    if ([kcid length]) {
        [connectionController setConnectionKeychainID:kcid];
        [connectionController setConnectionKeychainItemName:[keychain nameForFavoriteName:[connectionController name] id:kcid]];
        [connectionController setConnectionKeychainItemAccount:[keychain accountForUser:[connectionController user] host:[connectionController host] database:[connection objectForKey:@"database"]]];
    }

    // Set password - if not in SPF file try to get it via the KeyChain
    if ([connection objectForKey:@"password"]) {
        [connectionController setPassword:[connection objectForKey:@"password"]];
    }
    else {
        NSString *pw = [connectionController keychainPassword];
        if (pw) [connectionController setPassword:pw];
    }

    // Set the socket details, whether or not the type is a socket
    if ([connection objectForKey:@"socket"])                 [connectionController setSocket:[connection objectForKey:@"socket"]];
    // Set SSH details if available, whether or not the SSH type is currently active (to allow fallback on failure)
    if ([connection objectForKey:@"ssh_host"])               [connectionController setSshHost:[connection objectForKey:@"ssh_host"]];
    if ([connection objectForKey:@"ssh_user"])               [connectionController setSshUser:[connection objectForKey:@"ssh_user"]];
    if ([connection objectForKey:@"ssh_keyLocationEnabled"]) [connectionController setSshKeyLocationEnabled:[[connection objectForKey:@"ssh_keyLocationEnabled"] intValue]];
    if ([connection objectForKey:@"ssh_keyLocation"])        [connectionController setSshKeyLocation:[connection objectForKey:@"ssh_keyLocation"]];
    if ([connection objectForKey:@"ssh_port"])               [connectionController setSshPort:[NSString stringWithFormat:@"%ld", (long)[[connection objectForKey:@"ssh_port"] integerValue]]];

    // Set the SSH password - if not in SPF file try to get it via the KeyChain
    if ([connection objectForKey:@"ssh_password"]) {
        [connectionController setSshPassword:[connection objectForKey:@"ssh_password"]];
    }
    else {
        if ([kcid length]) {
            [connectionController setConnectionSSHKeychainItemName:[keychain nameForSSHForFavoriteName:[connectionController name] id:kcid]];
            [connectionController setConnectionSSHKeychainItemAccount:[keychain accountForSSHUser:[connectionController sshUser] sshHost:[connectionController sshHost]]];
        }
        NSString *sshpw = [self keychainPasswordForSSHConnection:nil];
        if(sshpw) [connectionController setSshPassword:sshpw];
    }

    // Restore the selected database if saved
    if ([connection objectForKey:@"database"]) [connectionController setDatabase:[connection objectForKey:@"database"]];

    // Store session details - if provided - for later setting once the connection is established
    if ([stateDetails objectForKey:@"session"]) {
        spfSession = [NSDictionary dictionaryWithDictionary:[stateDetails objectForKey:@"session"]];
    }

    // Restore favourites and history
    id o;
    if ((o = [stateDetails objectForKey:SPQueryFavorites])) [spfPreferences setObject:o forKey:SPQueryFavorites];
    if ((o = [stateDetails objectForKey:SPQueryHistory]))   [spfPreferences setObject:o forKey:SPQueryHistory];
    if ((o = [stateDetails objectForKey:SPContentFilters])) [spfPreferences setObject:o forKey:SPContentFilters];

    [connectionController updateSSLInterface:self];

    // Autoconnect if appropriate
    if ([stateDetails objectForKey:@"auto_connect"] && [[stateDetails valueForKey:@"auto_connect"] boolValue]) {
        [self connect];
    }

    return YES;
}

/**
 * Initialise the document with the connection file at the supplied path.
 * Returns whether the document was initialised successfully.
 */
- (BOOL)setStateFromConnectionFile:(NSString *)path {
    NSString *encryptpw = nil;
    NSMutableDictionary *data = nil;
    NSDictionary *spf = nil;
    NSError *error = nil;

    // Read the property list data, and unserialize it.
    NSData *pData = [NSData dataWithContentsOfFile:path options:NSUncachedRead error:&error];

    if(pData && !error) {
        spf = [NSPropertyListSerialization propertyListWithData:pData
                                                        options:NSPropertyListImmutable
                                                         format:NULL
                                                          error:&error];
    }

    if (!spf || error) {
        NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Connection data file couldn't be read. (%@)", @"error while reading connection data file"), [error localizedDescription]];
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error while reading connection data file", @"error while reading connection data file") message:message callback:nil];
        [self closeAndDisconnect];
        return NO;
    }

    // If the .spf format is unhandled, error.
    if (![[spf objectForKey:SPFFormatKey] isEqualToString:SPFConnectionContentType]) {
        NSString *message = [NSString stringWithFormat:NSLocalizedString(@"The chosen file “%@” contains ‘%@’ data.", @"message while reading a spf file which matches non-supported formats."), path, [spf objectForKey:SPFFormatKey]];
        [NSAlert createWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Unknown file format", @"warning")] message:message callback:nil];
        [self closeAndDisconnect];
        return NO;
    }

    // Error if the expected data source wasn't present in the file
    if (![spf objectForKey:@"data"]) {
        [NSAlert createWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Error while reading connection data file", @"error while reading connection data file")] message:NSLocalizedString(@"No data found.", @"no data found") callback:nil];
        [self closeAndDisconnect];
        return NO;
    }

    // Ask for a password if SPF file passwords were encrypted, via a sheet
    if ([spf objectForKey:@"encrypted"] && [[spf valueForKey:@"encrypted"] boolValue]) {
        if([self isSaveInBundle] && [[SPAppDelegate spfSessionDocData] objectForKey:@"e_string"]) {
            encryptpw = [[SPAppDelegate spfSessionDocData] objectForKey:@"e_string"];
        } else {
            [inputTextWindowHeader setStringValue:NSLocalizedString(@"Connection file is encrypted", @"Connection file is encrypted")];
            [inputTextWindowMessage setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Please enter the password for ‘%@’:", @"Please enter the password"), [path lastPathComponent]]];
            [inputTextWindowSecureTextField setStringValue:@""];
            [inputTextWindowSecureTextField selectText:nil];

            [[self.parentWindowController window] beginSheet:inputTextWindow completionHandler:nil];
            // wait for encryption password
            NSModalSession session = [NSApp beginModalSessionForWindow:inputTextWindow];
            for (;;) {

                // Execute code on DefaultRunLoop
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];

                // Break the run loop if editSheet was closed
                if ([NSApp runModalSession:session] != NSModalResponseContinue || ![inputTextWindow isVisible]) break;

                // Execute code on DefaultRunLoop
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];

            }
            [NSApp endModalSession:session];
            [inputTextWindow orderOut:nil];
            [NSApp endSheet:inputTextWindow];

            if (passwordSheetReturnCode) {
                encryptpw = [inputTextWindowSecureTextField stringValue];
                if ([self isSaveInBundle]) {
                    NSMutableDictionary *spfSessionData = [NSMutableDictionary dictionary];
                    [spfSessionData addEntriesFromDictionary:[SPAppDelegate spfSessionDocData]];
                    [spfSessionData setObject:encryptpw forKey:@"e_string"];
                    [SPAppDelegate setSpfSessionDocData:spfSessionData];
                }
            } else {
                [self closeAndDisconnect];
                return NO;
            }
        }
    }

    if ([[spf objectForKey:@"data"] isKindOfClass:[NSDictionary class]])
        data = [NSMutableDictionary dictionaryWithDictionary:[spf objectForKey:@"data"]];

    // If a content selection data key exists in the session, decode it
    if ([[[data objectForKey:@"session"] objectForKey:@"contentSelection"] isKindOfClass:[NSData class]]) {
        NSMutableDictionary *sessionInfo = [NSMutableDictionary dictionaryWithDictionary:[data objectForKey:@"session"]];
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:[sessionInfo objectForKey:@"contentSelection"]];
        [sessionInfo setObject:[unarchiver decodeObjectForKey:@"data"] forKey:@"contentSelection"];
        [unarchiver finishDecoding];
        [data setObject:sessionInfo forKey:@"session"];
    }

    else if ([[spf objectForKey:@"data"] isKindOfClass:[NSData class]]) {
        NSData *decryptdata = nil;
        decryptdata = [[NSMutableData alloc] initWithData:[(NSData *)[spf objectForKey:@"data"] dataDecryptedWithPassword:encryptpw]];
        if (decryptdata != nil && [decryptdata length]) {
            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:decryptdata];
            data = [NSMutableDictionary dictionaryWithDictionary:(NSDictionary *)[unarchiver decodeObjectForKey:@"data"]];
            [unarchiver finishDecoding];
        }
        if (data == nil) {
            [NSAlert createWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Error while reading connection data file", @"error while reading connection data file")] message:NSLocalizedString(@"Wrong data format or password.", @"wrong data format or password") callback:nil];
            [self closeAndDisconnect];
            return NO;
        }
    }

    // Ensure the data was read correctly, and has connection details
    if (!data || ![data objectForKey:@"connection"]) {
        NSString *informativeText;
        if (!data) {
            informativeText = NSLocalizedString(@"Wrong data format.", @"wrong data format");
        } else {
            informativeText = NSLocalizedString(@"No connection data found.", @"no connection data found");
        }
        [NSAlert createWarningAlertWithTitle:[NSString stringWithFormat:NSLocalizedString(@"Error while reading connection data file", @"error while reading connection data file")] message:informativeText callback:nil];
        [self closeAndDisconnect];
        return NO;
    }

    // Move favourites and history into the data dictionary to pass to setState:
    // SPQueryHistory is no longer saved to the SPF file, so it was causing an exception here (it was adding nil to the spf dict), skipping out of the method and not connecting
    // or restoring the query screen content. See commit 96063541
    if([spf objectForKey:SPQueryFavorites]){
        [data setObject:[spf objectForKey:SPQueryFavorites] forKey:SPQueryFavorites];
    }
    if([spf objectForKey:SPQueryHistory]){
        [data setObject:[spf objectForKey:SPQueryHistory] forKey:SPQueryHistory];
    }
    if([spf objectForKey:SPContentFilters]){
        [data setObject:[spf objectForKey:SPContentFilters] forKey:SPContentFilters];
    }

    // Ensure the encryption status is stored in the spfDocData store for future saves
    [spfDocData setObject:@NO forKey:@"encrypted"];
    if (encryptpw != nil) {
        [spfDocData setObject:@YES forKey:@"encrypted"];
        [spfDocData setObject:encryptpw forKey:@"e_string"];
    }
    encryptpw = nil;

    // If session data is available, ensure it is marked for save
    if ([data objectForKey:@"session"]) {
        [spfDocData setObject:@YES forKey:@"include_session"];
    }

    if (![self isSaveInBundle]) {
        NSURL *newURL = [NSURL fileURLWithPath:path];
        [self setFileURL:newURL];
    }

    [spfDocData setObject:[NSNumber numberWithBool:([[data objectForKey:@"connection"] objectForKey:@"password"]) ? YES : NO] forKey:@"save_password"];

    [spfDocData setObject:@NO forKey:@"auto_connect"];

    if([spf objectForKey:@"auto_connect"] && [[spf valueForKey:@"auto_connect"] boolValue]) {
        [spfDocData setObject:@YES forKey:@"auto_connect"];
        [data setObject:@YES forKey:@"auto_connect"];
    }

    // Set the state dictionary, triggering an autoconnect if appropriate
    [self setState:data];

    return YES;
}

/**
 * Restore the session from SPF file if given.
 */
- (void)restoreSession
{
    @autoreleasepool {
        // Check and set the table
        NSArray *tables = [tablesListInstance tables];

        NSUInteger tableIndex = [tables indexOfObject:[spfSession objectForKey:@"table"]];

        // Restore toolbar setting
        if ([spfSession objectForKey:@"isToolbarVisible"]) {
            [[self.mainToolbar onMainThread] setVisible:[[spfSession objectForKey:@"isToolbarVisible"] boolValue]];
        }

        // Reset database view encoding if differs from default
        if ([spfSession objectForKey:@"connectionEncoding"] && ![[mySQLConnection encoding] isEqualToString:[spfSession objectForKey:@"connectionEncoding"]]) {
            [self setConnectionEncoding:[spfSession objectForKey:@"connectionEncoding"] reloadingViews:YES];
        }

        if (tableIndex != NSNotFound) {
            // Set table content details for restore
            if ([spfSession objectForKey:@"contentSortCol"])    [tableContentInstance setSortColumnNameToRestore:[spfSession objectForKey:@"contentSortCol"] isAscending:[[spfSession objectForKey:@"contentSortColIsAsc"] boolValue]];
            if ([spfSession objectForKey:@"contentPageNumber"]) [tableContentInstance setPageToRestore:[[spfSession objectForKey:@"pageNumber"] integerValue]];
            if ([spfSession objectForKey:@"contentViewport"])   [tableContentInstance setViewportToRestore:NSRectFromString([spfSession objectForKey:@"contentViewport"])];
            if ([spfSession objectForKey:@"contentFilterV2"])   [tableContentInstance setFiltersToRestore:[spfSession objectForKey:@"contentFilterV2"]];

            // Select table
            [[tablesListInstance onMainThread] selectTableAtIndex:@(tableIndex)];

            // Restore table selection indexes
            if ([spfSession objectForKey:@"contentSelection"]) {
                [tableContentInstance setSelectionToRestore:[spfSession objectForKey:@"contentSelection"]];
            }

            // Scroll to table
            [[tablesListInstance->tablesListView onMainThread] scrollRowToVisible:tableIndex];
        }

        // update UI on main thread
        SPMainQSync(^{
            // Select view
            NSString *view = [self->spfSession objectForKey:@"view"];

            if ([view isEqualToString:@"SP_VIEW_STRUCTURE"]) {
                [self viewStructure];
            } else if ([view isEqualToString:@"SP_VIEW_CONTENT"]) {
                [self viewContent];
            } else if ([view isEqualToString:@"SP_VIEW_CUSTOMQUERY"]) {
                [self viewQuery];
            } else if ([view isEqualToString:@"SP_VIEW_STATUS"]) {
                [self viewStatus];
            } else if ([view isEqualToString:@"SP_VIEW_RELATIONS"]) {
                [self viewRelations];
            } else if ([view isEqualToString:@"SP_VIEW_TRIGGERS"]) {
                [self viewTriggers];
            }
            [self updateWindowTitle:self];
        });

        // End the task
        [self endTask];
    }
}

#pragma mark -
#pragma mark Connection controller delegate methods

/**
 * Invoked by the connection controller when it starts the process of initiating a connection.
 */
- (void)connectionControllerInitiatingConnection:(SPConnectionController *)controller
{
    [[self.parentWindowController window] setTitle:NSLocalizedString(@"Connecting…", @"window title string indicating that sp is connecting")];
}

/**
 * Invoked by the connection controller when the attempt to initiate a connection failed.
 */
- (void)connectionControllerConnectAttemptFailed:(SPConnectionController *)controller
{
    // Reset the window title
    [self updateWindowTitle:self];
}

- (SPConnectionController*)connectionController
{
    return connectionController;
}

#pragma mark -
#pragma mark Scheme scripting methods

/**
 * Called by handleSchemeCommand: to break a while loop
 */
- (void)setTimeout
{
    _workingTimeout = YES;
}

/**
 * Process passed URL scheme command and wait (timeouted) for the document if it's busy or not yet connected
 */
- (void)handleSchemeCommand:(NSDictionary*)commandDict
{
    if(!commandDict) return;

    NSArray *params = [commandDict objectForKey:@"parameter"];
    if(![params count]) {
        NSLog(@"No URL scheme command passed");
        NSBeep();
        return;
    }

    NSString *command = [params objectAtIndex:0];
    NSString *docProcessID = [self processID];
    if(!docProcessID) docProcessID = @"";

    // Wait for self
    _workingTimeout = NO;
    // the following while loop waits maximal 5secs
    [self performSelector:@selector(setTimeout) withObject:nil afterDelay:5.0];
    while (_isWorkingLevel || !_isConnected) {
        if(_workingTimeout) break;
        // Do not block self
        NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                            untilDate:[NSDate distantPast]
                                               inMode:NSDefaultRunLoopMode
                                              dequeue:YES];
        if(event) [NSApp sendEvent:event];

    }

    if ([command isEqualToString:@"SelectDocumentView"]) {
        if([params count] == 2) {
            NSString *view = [params objectAtIndex:1];
            if([view length]) {
                NSString *viewName = [view lowercaseString];
                if ([viewName hasPrefix:@"str"]) {
                    [self viewStructure];
                } else if([viewName hasPrefix:@"con"]) {
                    [self viewContent];
                } else if([viewName hasPrefix:@"que"]) {
                    [self viewQuery];
                } else if([viewName hasPrefix:@"tab"]) {
                    [self viewStatus];
                } else if([viewName hasPrefix:@"rel"]) {
                    [self viewRelations];
                } else if([viewName hasPrefix:@"tri"]) {
                    [self viewTriggers];
                }
                [self updateWindowTitle:self];
            }
        }
        return;
    }

    if([command isEqualToString:@"SelectTable"]) {
        if([params count] == 2) {
            NSString *tableName = [params objectAtIndex:1];
            if([tableName length]) {
                [tablesListInstance selectItemWithName:tableName];
            }
        }
        return;
    }

    if([command isEqualToString:@"SelectTables"]) {
        if([params count] > 1) {
            [tablesListInstance selectItemsWithNames:[params subarrayWithRange:NSMakeRange(1, [params count]-1)]];
        }
        return;
    }

    if([command isEqualToString:@"SelectDatabase"]) {
        if([params count] > 1) {
            NSString *dbName = [params objectAtIndex:1];
            NSString *tableName = nil;
            if([dbName length]) {
                if([params count] == 3) {
                    tableName = [params objectAtIndex:2];
                }
                [self selectDatabase:dbName item:tableName];
            }
        }
        return;
    }

    // ==== the following commands need an authentication for safety reasons

    // Authenticate command
    if(![docProcessID isEqualToString:[commandDict objectForKey:@"id"]]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Remote Error", @"remote error") message:NSLocalizedString(@"URL scheme command couldn't authenticated", @"URL scheme command couldn't authenticated") callback:nil];
        return;
    }

    if([command isEqualToString:@"SetSelectedTextRange"]) {
        if([params count] > 1) {
            id firstResponder = [[self.parentWindowController window] firstResponder];
            if([firstResponder isKindOfClass:[NSTextView class]]) {
                NSRange theRange = NSIntersectionRange(NSRangeFromString([params objectAtIndex:1]), NSMakeRange(0, [[firstResponder string] length]));
                if(theRange.location != NSNotFound) {
                    [firstResponder setSelectedRange:theRange];
                }
                return;
            }
            NSBeep();
        }
        return;
    }

    if([command isEqualToString:@"InsertText"]) {
        if([params count] > 1) {
            id firstResponder = [[self.parentWindowController window] firstResponder];
            if([firstResponder isKindOfClass:[NSTextView class]]) {
                [((NSTextView *)firstResponder).textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:[params objectAtIndex:1]]];
                return;
            }
            NSBeep();
        }
        return;
    }

    if([command isEqualToString:@"SetText"]) {
        if([params count] > 1) {
            id firstResponder = [[self.parentWindowController window] firstResponder];
            if([firstResponder isKindOfClass:[NSTextView class]]) {
                [(NSTextView *)firstResponder setSelectedRange:NSMakeRange(0, [[firstResponder string] length])];
                [((NSTextView *)firstResponder).textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:[params objectAtIndex:1]]];
                return;
            }
            NSBeep();
        }
        return;
    }

    if([command isEqualToString:@"SelectTableRows"]) {
        id firstResponder = [[NSApp keyWindow] firstResponder];
        if([params count] > 1 && [firstResponder respondsToSelector:@selector(selectTableRows:)]) {
            [(SPCopyTable *)firstResponder selectTableRows:[params subarrayWithRange:NSMakeRange(1, [params count]-1)]];
        }
        return;
    }

    if([command isEqualToString:@"ReloadContentTable"]) {
        [tableContentInstance reloadTable:self];
        return;
    }

    if([command isEqualToString:@"ReloadTablesList"]) {
        [tablesListInstance updateTables:self];
        return;
    }

    if([command isEqualToString:@"ReloadContentTableWithWHEREClause"]) {
        NSString *queryFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryInputPathHeader stringByExpandingTildeInPath], docProcessID];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL isDir;
        if([fileManager fileExistsAtPath:queryFileName isDirectory:&isDir] && !isDir) {
            NSError *inError = nil;
            NSString *query = [NSString stringWithContentsOfFile:queryFileName encoding:NSUTF8StringEncoding error:&inError];
            [fileManager removeItemAtPath:queryFileName error:nil];
            if(inError == nil && query && [query length]) {
                [tableContentInstance filterTable:query];
            }
        }
        return;
    }

    if([command isEqualToString:@"RunQueryInQueryEditor"]) {
        NSString *queryFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryInputPathHeader stringByExpandingTildeInPath], docProcessID];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL isDir;
        if([fileManager fileExistsAtPath:queryFileName isDirectory:&isDir] && !isDir) {
            NSError *inError = nil;
            NSString *query = [NSString stringWithContentsOfFile:queryFileName encoding:NSUTF8StringEncoding error:&inError];
            [fileManager removeItemAtPath:queryFileName error:nil];
            if(inError == nil && query && [query length]) {
                [customQueryInstance performQueries:@[query] withCallback:NULL];
            }
        }
        return;
    }

    if([command isEqualToString:@"CreateSyntaxForTables"]) {

        if([params count] > 1) {

            NSString *queryFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryInputPathHeader stringByExpandingTildeInPath], docProcessID];
            NSString *resultFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultPathHeader stringByExpandingTildeInPath], docProcessID];
            NSString *metaFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultMetaPathHeader stringByExpandingTildeInPath], docProcessID];
            NSString *statusFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultStatusPathHeader stringByExpandingTildeInPath], docProcessID];
            NSFileManager *fileManager = [NSFileManager defaultManager];
            NSString *status = @"0";
            BOOL userTerminated = NO;
            BOOL doSyntaxHighlighting = NO;
            BOOL doSyntaxHighlightingViaCSS = NO;

            if([[params lastObject] hasPrefix:@"html"]) {
                doSyntaxHighlighting = YES;
                if([[params lastObject] hasSuffix:@"css"]) {
                    doSyntaxHighlightingViaCSS = YES;
                }
            }

            if(doSyntaxHighlighting && [params count] < 3) return;

            BOOL changeEncoding = ![[mySQLConnection encoding] hasPrefix:@"utf8"];


            NSArray *items = [params subarrayWithRange:NSMakeRange(1, [params count]-( (doSyntaxHighlighting) ? 2 : 1) )];
            NSArray *availableItems = [tablesListInstance tables];
            NSArray *availableItemTypes = [tablesListInstance tableTypes];
            NSMutableString *result = [NSMutableString string];

            for(NSString* item in items) {

                NSEvent* event = [NSApp currentEvent];
                if ([event type] == NSEventTypeKeyDown) {
                    unichar key = [[event characters] length] == 1 ? [[event characters] characterAtIndex:0] : 0;
                    if (([event modifierFlags] & NSEventModifierFlagCommand) && key == '.') {
                        userTerminated = YES;
                        break;
                    }
                }

                NSInteger itemType = SPTableTypeNone;
                NSUInteger i;

                // Loop through the unfiltered tables/views to find the desired item
                for (i = 0; i < [availableItems count]; i++) {
                    itemType = [[availableItemTypes objectAtIndex:i] integerValue];
                    if (itemType == SPTableTypeNone) continue;
                    if ([[availableItems objectAtIndex:i] isEqualToString:item]) {
                        break;
                    }
                }
                // If no match found, continue
                if (itemType == SPTableTypeNone) continue;

                NSString *itemTypeStr;
                NSInteger queryCol;

                switch(itemType) {
                    case SPTableTypeTable:
                    case SPTableTypeView:
                        itemTypeStr = @"TABLE";
                        queryCol = 1;
                        break;
                    case SPTableTypeProc:
                        itemTypeStr = @"PROCEDURE";
                        queryCol = 2;
                        break;
                    case SPTableTypeFunc:
                        itemTypeStr = @"FUNCTION";
                        queryCol = 2;
                        break;
                    default:
                        NSLog(@"%s: Unhandled SPTableType=%ld for item=%@ (skipping)", __func__, itemType, item);
                        continue;
                }

                // Ensure that queries are made in UTF8
                if (changeEncoding) {
                    [mySQLConnection storeEncodingForRestoration];
                    [mySQLConnection setEncoding:@"utf8mb4"];
                }

                // Get create syntax
                SPMySQLResult *queryResult = [mySQLConnection queryString:[NSString stringWithFormat:@"SHOW CREATE %@ %@",
                                                                           itemTypeStr,
                                                                           [item backtickQuotedString]]];
                [queryResult setReturnDataAsStrings:YES];

                if (changeEncoding) [mySQLConnection restoreStoredEncoding];

                if ( ![queryResult numberOfRows] ) {
                    //error while getting table structure
                    [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error", @"error") message:[NSString stringWithFormat:NSLocalizedString(@"Couldn't get create syntax.\nMySQL said: %@", @"message of panel when table information cannot be retrieved"), [mySQLConnection lastErrorMessage]] callback:nil];
                    status = @"1";
                } else {
                    NSString *syntaxString = [[queryResult getRowAsArray] objectAtIndex:queryCol];

                    // A NULL value indicates that the user does not have permission to view the syntax
                    if ([syntaxString isNSNull]) {
                        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Permission Denied", @"Permission Denied") message:NSLocalizedString(@"The creation syntax could not be retrieved due to a permissions error.\n\nPlease check your user permissions with an administrator.", @"Create syntax permission denied detail") callback:nil];
                        return;
                    }
                    if(doSyntaxHighlighting) {
                        [result appendFormat:@"%@<br>", [SPAppDelegate doSQLSyntaxHighlightForString:[syntaxString createViewSyntaxPrettifier] cssLike:doSyntaxHighlightingViaCSS]];
                    } else {
                        [result appendFormat:@"%@\n", [syntaxString createViewSyntaxPrettifier]];
                    }
                }
            }

            [fileManager removeItemAtPath:queryFileName error:nil];
            [fileManager removeItemAtPath:resultFileName error:nil];
            [fileManager removeItemAtPath:metaFileName error:nil];
            [fileManager removeItemAtPath:statusFileName error:nil];

            if(userTerminated)
                status = @"1";

            if(![result writeToFile:resultFileName atomically:YES encoding:NSUTF8StringEncoding error:nil])
                status = @"1";

            // write status file as notification that query was finished
            BOOL succeed = [status writeToFile:statusFileName atomically:YES encoding:NSUTF8StringEncoding error:nil];
            if (!succeed) {
                NSBeep();
                [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"BASH Error", @"bash error") message:NSLocalizedString(@"Status file for sequelace url scheme command couldn't be written!", @"status file for sequelace url scheme command couldn't be written error message") callback:nil];
            }

        }
        return;
    }

    if([command isEqualToString:@"ExecuteQuery"]) {

        NSString *outputFormat = @"tab";
        if([params count] == 2)
            outputFormat = [params objectAtIndex:1];

        BOOL writeAsCsv = ([outputFormat isEqualToString:@"csv"]) ? YES : NO;

        NSString *queryFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryInputPathHeader stringByExpandingTildeInPath], docProcessID];
        NSString *resultFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultPathHeader stringByExpandingTildeInPath], docProcessID];
        NSString *metaFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultMetaPathHeader stringByExpandingTildeInPath], docProcessID];
        NSString *statusFileName = [NSString stringWithFormat:@"%@%@", [SPURLSchemeQueryResultStatusPathHeader stringByExpandingTildeInPath], docProcessID];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *status = @"0";
        BOOL isDir;
        BOOL userTerminated = NO;
        if([fileManager fileExistsAtPath:queryFileName isDirectory:&isDir] && !isDir) {

            NSError *inError = nil;
            NSString *query = [NSString stringWithContentsOfFile:queryFileName encoding:NSUTF8StringEncoding error:&inError];

            [fileManager removeItemAtPath:queryFileName error:nil];
            [fileManager removeItemAtPath:resultFileName error:nil];
            [fileManager removeItemAtPath:metaFileName error:nil];
            [fileManager removeItemAtPath:statusFileName error:nil];

            if(inError == nil && query && [query length]) {

                SPFileHandle *fh = [SPFileHandle fileHandleForWritingAtPath:resultFileName];
                if(!fh){
                    SPLog(@"Couldn't create file handle to %@", resultFileName);
                }

                SPMySQLResult *theResult = [mySQLConnection streamingQueryString:query];
                [theResult setReturnDataAsStrings:YES];
                if ([mySQLConnection queryErrored]) {
                    [fh writeData:[[NSString stringWithFormat:@"MySQL said: %@", [mySQLConnection lastErrorMessage]] dataUsingEncoding:NSUTF8StringEncoding]];
                    status = @"1";
                } else {

                    // write header
                    if(writeAsCsv)
                        [fh writeData:[[[theResult fieldNames] componentsJoinedAsCSV] dataUsingEncoding:NSUTF8StringEncoding]];
                    else
                        [fh writeData:[[[theResult fieldNames] componentsJoinedByString:@"\t"] dataUsingEncoding:NSUTF8StringEncoding]];
                    [fh writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];

                    NSArray *columnDefinition = [theResult fieldDefinitions];

                    // Write table meta data
                    NSMutableString *tableMetaData = [NSMutableString string];
                    for(NSDictionary* col in columnDefinition) {
                        [tableMetaData appendFormat:@"%@\t", [col objectForKey:@"type"]];
                        [tableMetaData appendFormat:@"%@\t", [col objectForKey:@"typegrouping"]];
                        [tableMetaData appendFormat:@"%@\t", ([col objectForKey:@"char_length"]) ? : @""];
                        [tableMetaData appendFormat:@"%@\t", [col objectForKey:@"UNSIGNED_FLAG"]];
                        [tableMetaData appendFormat:@"%@\t", [col objectForKey:@"AUTO_INCREMENT_FLAG"]];
                        [tableMetaData appendFormat:@"%@\t", [col objectForKey:@"PRI_KEY_FLAG"]];
                        [tableMetaData appendString:@"\n"];
                    }
                    NSError *err = nil;
                    [tableMetaData writeToFile:metaFileName
                                    atomically:YES
                                      encoding:NSUTF8StringEncoding
                                         error:&err];
                    if(err != nil) {
                        NSLog(@"Error while writing “%@”", tableMetaData);
                        NSBeep();
                        return;
                    }

                    // write data
                    NSUInteger i, j;
                    NSArray *theRow;
                    NSMutableString *result = [NSMutableString string];
                    if(writeAsCsv) {
                        for ( i = 0 ; i < [theResult numberOfRows]; i++ ) {
                            [result setString:@""];
                            theRow = [theResult getRowAsArray];
                            for( j = 0 ; j < [theRow count]; j++ ) {

                                NSEvent* event = [NSApp currentEvent];
                                if ([event type] == NSEventTypeKeyDown) {
                                    unichar key = [[event characters] length] == 1 ? [[event characters] characterAtIndex:0] : 0;
                                    if (([event modifierFlags] & NSEventModifierFlagCommand) && key == '.') {
                                        userTerminated = YES;
                                        break;
                                    }
                                }

                                if([result length]) [result appendString:@","];
                                id cell = [theRow safeObjectAtIndex:j];
                                if([cell isNSNull])
                                    [result appendString:@"\"NULL\""];
                                else if([cell isKindOfClass:[SPMySQLGeometryData class]])
                                    [result appendFormat:@"\"%@\"", [cell wktString]];
                                else if([cell isKindOfClass:[NSData class]]) {
                                    NSString *displayString = [[NSString alloc] initWithData:cell encoding:[mySQLConnection stringEncoding]];
                                    if (!displayString) displayString = [[NSString alloc] initWithData:cell encoding:NSASCIIStringEncoding];
                                    if (displayString) {
                                        [result appendFormat:@"\"%@\"", [displayString stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
                                    } else {
                                        [result appendString:@"\"\""];
                                    }
                                }
                                else
                                    [result appendFormat:@"\"%@\"", [[cell description] stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
                            }
                            if(userTerminated) break;
                            [result appendString:@"\n"];
                            [fh writeData:[result dataUsingEncoding:NSUTF8StringEncoding]];
                        }
                    }
                    else {
                        for ( i = 0 ; i < [theResult numberOfRows]; i++ ) {
                            [result setString:@""];
                            theRow = [theResult getRowAsArray];
                            for( j = 0 ; j < [theRow count]; j++ ) {

                                NSEvent* event = [NSApp currentEvent];
                                if ([event type] == NSEventTypeKeyDown) {
                                    unichar key = [[event characters] length] == 1 ? [[event characters] characterAtIndex:0] : 0;
                                    if (([event modifierFlags] & NSEventModifierFlagCommand) && key == '.') {
                                        userTerminated = YES;
                                        break;
                                    }
                                }

                                if([result length]) [result appendString:@"\t"];
                                id cell = [theRow safeObjectAtIndex:j];
                                if([cell isNSNull])
                                    [result appendString:@"NULL"];
                                else if([cell isKindOfClass:[SPMySQLGeometryData class]])
                                    [result appendFormat:@"%@", [cell wktString]];
                                else if([cell isKindOfClass:[NSData class]]) {
                                    NSString *displayString = [[NSString alloc] initWithData:cell encoding:[mySQLConnection stringEncoding]];
                                    if (!displayString) displayString = [[NSString alloc] initWithData:cell encoding:NSASCIIStringEncoding];
                                    if (displayString) {
                                        [result appendFormat:@"%@", [[displayString stringByReplacingOccurrencesOfString:@"\n" withString:@"↵"] stringByReplacingOccurrencesOfString:@"\t" withString:@"⇥"]];
                                    } else {
                                        [result appendString:@""];
                                    }
                                }
                                else
                                    [result appendString:[[[cell description] stringByReplacingOccurrencesOfString:@"\n" withString:@"↵"] stringByReplacingOccurrencesOfString:@"\t" withString:@"⇥"]];
                            }
                            if(userTerminated) break;
                            [result appendString:@"\n"];
                            [fh writeData:[result dataUsingEncoding:NSUTF8StringEncoding]];
                        }
                    }
                }
                [fh closeFile];
            }
        }

        if(userTerminated) {
            [SPTooltip showWithObject:NSLocalizedString(@"URL scheme command was terminated by user", @"URL scheme command was terminated by user") atLocation:[NSEvent mouseLocation]];
            status = @"1";
        }

        // write status file as notification that query was finished
        BOOL succeed = [status writeToFile:statusFileName atomically:YES encoding:NSUTF8StringEncoding error:nil];
        if(!succeed) {
            NSBeep();
            [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"BASH Error", @"bash error") message:NSLocalizedString(@"Status file for sequelace url scheme command couldn't be written!", @"status file for sequelace url scheme command couldn't be written error message") callback:nil];
        }
        return;
    }

    [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Remote Error", @"remote error") message:[NSString stringWithFormat:NSLocalizedString(@"URL scheme command “%@” unsupported", @"URL scheme command “%@” unsupported"), command] callback:nil];
}

- (void)registerActivity:(NSDictionary *)commandDict
{
    [runningActivitiesArray addObject:commandDict];
    [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:SPActivitiesUpdateNotification object:self];

    if([runningActivitiesArray count] || [[SPAppDelegate runningActivities] count])
        [self performSelector:@selector(setActivityPaneHidden:) withObject:@0 afterDelay:1.0];
    else {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(setActivityPaneHidden:)
                                                   object:@0];
        [self setActivityPaneHidden:@1];
    }

}

- (void)removeRegisteredActivity:(NSInteger)pid
{

    for(id cmd in runningActivitiesArray) {
        if([[cmd objectForKey:@"pid"] integerValue] == pid) {
            [runningActivitiesArray removeObject:cmd];
            break;
        }
    }

    if([runningActivitiesArray count] || [[SPAppDelegate runningActivities] count])
        [self performSelector:@selector(setActivityPaneHidden:) withObject:@0 afterDelay:1.0];
    else {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(setActivityPaneHidden:)
                                                   object:@0];
        [self setActivityPaneHidden:@1];
    }

    [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:SPActivitiesUpdateNotification object:self];
}

- (void)setActivityPaneHidden:(NSNumber *)hide
{
    if (hide.boolValue) {
        [documentActivityScrollView setHidden:YES];
        [tableInfoScrollView setHidden:NO];
    }
    else {
        [tableInfoScrollView setHidden:YES];
        [documentActivityScrollView setHidden:NO];
    }
}

- (NSArray *)runningActivities
{
    return runningActivitiesArray;
}

- (NSDictionary *)shellVariables
{
    if (!_isConnected) return @{};

    NSMutableDictionary *env = [NSMutableDictionary dictionary];

    if (tablesListInstance) {

        if ([tablesListInstance selectedDatabase]) {
            [env setObject:[tablesListInstance selectedDatabase] forKey:SPBundleShellVariableSelectedDatabase];
        }

        if ([tablesListInstance tableName]) {
            [env setObject:[tablesListInstance tableName] forKey:SPBundleShellVariableSelectedTable];
        }

        if ([tablesListInstance selectedTableItems]) {
            [env setObject:[[tablesListInstance selectedTableItems] componentsJoinedByString:@"\t"] forKey:SPBundleShellVariableSelectedTables];
        }

        if ([tablesListInstance allDatabaseNames]) {
            [env setObject:[[tablesListInstance allDatabaseNames] componentsJoinedByString:@"\t"] forKey:SPBundleShellVariableAllDatabases];
        }

        if ([self user]) {
            [env setObject:[self user] forKey:SPBundleShellVariableCurrentUser];
        }

        if ([self host]) {
            [env setObject:[self host] forKey:SPBundleShellVariableCurrentHost];
        }

        if ([self port]) {
            [env setObject:[self port] forKey:SPBundleShellVariableCurrentPort];
        }

        [env setObject:[[tablesListInstance allTableNames] componentsJoinedByString:@"\t"] forKey:SPBundleShellVariableAllTables];
        [env setObject:[[tablesListInstance allViewNames] componentsJoinedByString:@"\t"] forKey:SPBundleShellVariableAllViews];
        [env setObject:[[tablesListInstance allFunctionNames] componentsJoinedByString:@"\t"] forKey:SPBundleShellVariableAllFunctions];
        [env setObject:[[tablesListInstance allProcedureNames] componentsJoinedByString:@"\t"] forKey:SPBundleShellVariableAllProcedures];

        [env setObject:([self databaseEncoding]) ? : @"" forKey:SPBundleShellVariableDatabaseEncoding];
    }

    [env setObject:@"mysql" forKey:SPBundleShellVariableRDBMSType];

    if ([self mySQLVersion]) {
        [env setObject:[self mySQLVersion] forKey:SPBundleShellVariableRDBMSVersion];
    }

    return env;
}

#pragma mark -
#pragma mark Text field delegate methods

/**
 * When adding a database, enable the button only if the new name has a length.
 */
- (void)controlTextDidChange:(NSNotification *)notification
{
    id object = [notification object];

    if (object == databaseNameField) {
        [addDatabaseButton setEnabled:([[databaseNameField stringValue] length] > 0 && ![allDatabases containsObject: [databaseNameField stringValue]])];
    }
    else if (object == databaseCopyNameField) {
        [copyDatabaseButton setEnabled:([[databaseCopyNameField stringValue] length] > 0 && ![allDatabases containsObject: [databaseCopyNameField stringValue]])];
    }
    else if (object == databaseRenameNameField) {
        [renameDatabaseButton setEnabled:([[databaseRenameNameField stringValue] length] > 0 && ![allDatabases containsObject: [databaseRenameNameField stringValue]])];
    }
    else if (object == self.saveConnectionEncryptString) {
        [self.saveConnectionEncryptString setStringValue:[self.saveConnectionEncryptString stringValue]];
    }
}

#pragma mark -
#pragma mark General sheet delegate methods

- (NSRect)window:(NSWindow *)window willPositionSheet:(NSWindow *)sheet usingRect:(NSRect)rect {

    // Locate the sheet "Reset Auto Increment" just centered beneath the chosen index row
    // if Structure Pane is active
    if([self currentlySelectedView] == SPTableViewStructure
       && [[sheet title] isEqualToString:@"Reset Auto Increment"]) {

        id it = [tableSourceInstance valueForKeyPath:@"indexesTableView"];
        NSRect mwrect = [[NSApp mainWindow] frame];
        NSRect ltrect = [[tablesListInstance valueForKeyPath:@"tablesListView"] frame];
        NSRect rowrect = [it rectOfRow:[it selectedRow]];
        rowrect.size.width = mwrect.size.width - ltrect.size.width;
        rowrect.origin.y -= [it rowHeight]/2.0f+2;
        rowrect.origin.x -= 8;
        return [it convertRect:rowrect toView:nil];

    }

    return rect;
}

#pragma mark -
#pragma mark SplitView delegate methods

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex
{
    if (dividerIndex == 0 && proposedMinimumPosition < 40) {
        return 40;
    }
    return proposedMinimumPosition;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex
{
    //the right side of the SP window must be at least 505px wide or the UI will break!
    if(dividerIndex == 0) {
        return proposedMaximumPosition - 505;
    }
    return proposedMaximumPosition;
}

#pragma mark -
#pragma mark Datasource methods

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return (statusTableView && aTableView == statusTableView) ? [statusValues count] : 0;
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    if (statusTableView && aTableView == statusTableView && rowIndex < (NSInteger)[statusValues count]) {
        if ([[aTableColumn identifier] isEqualToString:@"table_name"]) {
            if([[statusValues objectAtIndex:rowIndex] objectForKey:@"table_name"])
                return [[statusValues objectAtIndex:rowIndex] objectForKey:@"table_name"];
            else if([[statusValues objectAtIndex:rowIndex] objectForKey:@"Table"])
                return [[statusValues objectAtIndex:rowIndex] objectForKey:@"Table"];
            return @"";
        }
        else if ([[aTableColumn identifier] isEqualToString:@"msg_status"]) {
            if([[statusValues objectAtIndex:rowIndex] objectForKey:@"Msg_type"])
                return [[[statusValues objectAtIndex:rowIndex] objectForKey:@"Msg_type"] capitalizedString];
            return @"";
        }
        else if ([[aTableColumn identifier] isEqualToString:@"msg_text"]) {
            if([[statusValues objectAtIndex:rowIndex] objectForKey:@"Msg_text"]) {
                [[aTableColumn headerCell] setStringValue:NSLocalizedString(@"Message",@"message column title")];
                return [[statusValues objectAtIndex:rowIndex] objectForKey:@"Msg_text"];
            }
            else if([[statusValues objectAtIndex:rowIndex] objectForKey:@"Checksum"]) {
                [[aTableColumn headerCell] setStringValue:@"Checksum"];
                return [[statusValues objectAtIndex:rowIndex] objectForKey:@"Checksum"];
            }
            return @"";
        }
    }
    return nil;
}

- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    return NO;
}

#pragma mark -
#pragma mark Status accessory view

- (IBAction)copyChecksumFromSheet:(id)sender
{
    NSMutableString *tmp = [NSMutableString string];
    for(id row in statusValues) {
        if ([row objectForKey:@"Msg_type"]) {
            [tmp appendFormat:@"%@\t%@\t%@\n",
             [[row objectForKey:@"Table"] description],
             [[row objectForKey:@"Msg_type"] description],
             [[row objectForKey:@"Msg_text"] description]];
        } else {
            [tmp appendFormat:@"%@\t%@\n",
             [[row objectForKey:@"Table"] description],
             [[row objectForKey:@"Checksum"] description]];
        }
    }

    if ( [tmp length] )
    {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];

        [pb declareTypes:@[NSPasteboardTypeTabularText, NSPasteboardTypeString] owner:nil];

        [pb setString:tmp forType:NSPasteboardTypeString];
        [pb setString:tmp forType:NSPasteboardTypeTabularText];
    }
}

- (void)setIsSavedInBundle:(BOOL)savedInBundle
{
    _isSavedInBundle = savedInBundle;
}

#pragma mark -
#pragma mark Private API

/**
 * Copies the current database (and optionally it's content) on a separate thread.
 *
 * This method *MUST* be called from the UI thread!
 */
- (void)_copyDatabase
{
    NSString *newDatabaseName = [databaseCopyNameField stringValue];

    if ([newDatabaseName isEqualToString:@""]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error", @"error") message:NSLocalizedString(@"Database must have a name.", @"message of panel when no db name is given") callback:nil];
        return;
    }

    NSDictionary *databaseDetails = @{
        SPNewDatabaseDetails : [self createDatabaseInfo],
        SPNewDatabaseName : newDatabaseName,
        SPNewDatabaseCopyContent : @([copyDatabaseDataButton state] == NSControlStateValueOn)
    };

    [self startTaskWithDescription:[NSString stringWithFormat:NSLocalizedString(@"Copying database '%@'...", @"Copying database task description"), [self database]]];

    if ([NSThread isMainThread]) {
        [NSThread detachNewThreadWithName:SPCtxt(@"SPDatabaseDocument copy database task", self)
                                   target:self
                                 selector:@selector(_copyDatabaseWithDetails:)
                                   object:databaseDetails];;
    }
    else {
        [self _copyDatabaseWithDetails:databaseDetails];
    }
}

- (void)_copyDatabaseWithDetails:(NSDictionary *)databaseDetails
{
    @autoreleasepool
    {
        SPDatabaseCopy *databaseCopy = [[SPDatabaseCopy alloc] init];

        [databaseCopy setConnection:[self getConnection]];

        NSString *newDatabaseName = [databaseDetails objectForKey:SPNewDatabaseName];

        BOOL success = [databaseCopy copyDatabaseFrom:[databaseDetails objectForKey:SPNewDatabaseDetails]
                                                   to:newDatabaseName
                                          withContent:[[databaseDetails objectForKey:SPNewDatabaseCopyContent] boolValue]];

        // Select newly created database
        [[self onMainThread] selectDatabase:newDatabaseName item:nil];

        // Update database list
        [[self onMainThread] setDatabases];

        // inform observers that a new database was added
        [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:SPDatabaseCreatedRemovedRenamedNotification object:nil];

        [self endTask];

        if (!success) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Unable to copy database", @"unable to copy database message") message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while trying to copy the database '%@' to '%@'.", @"unable to copy database message informative message"), [databaseDetails[SPNewDatabaseDetails] databaseName], newDatabaseName] callback:nil];
            });
        }
    }
}

/**
 * This method *MUST* be called from the UI thread!
 */
- (void)_renameDatabase
{
    NSString *newDatabaseName = [databaseRenameNameField stringValue];

    if ([newDatabaseName isEqualToString:@""]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error", @"error") message:NSLocalizedString(@"Database must have a name.", @"message of panel when no db name is given") callback:nil];
        return;
    }

    SPLog(@"_renameDatabase");
    SPDatabaseRename *dbActionRename = [[SPDatabaseRename alloc] init];

    [dbActionRename setTablesList:tablesListInstance];
    [dbActionRename setConnection:[self getConnection]];

    if ([dbActionRename renameDatabaseFrom:[self createDatabaseInfo] to:newDatabaseName]) {
        [self setDatabases];
        [self selectDatabase:newDatabaseName item:nil];
        // inform observers that a new database was added
        [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:SPDatabaseCreatedRemovedRenamedNotification object:nil];
    }
    else {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Unable to rename database", @"unable to rename database message") message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while trying to rename the database '%@' to '%@'.", @"unable to rename database message informative message"), [self database], newDatabaseName] callback:nil];
    }
}

/**
 * Adds a new database.
 *
 * This method *MUST* be called from the UI thread!
 */
- (void)_addDatabase
{
    // This check is not necessary anymore as the add database button is now only enabled if the name field
    // has a length greater than zero. We'll leave it in just in case.
    if ([[databaseNameField stringValue] isEqualToString:@""]) {
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error", @"error") message:NSLocalizedString(@"Database must have a name.", @"message of panel when no db name is given") callback:nil];
        return;
    }

    // As we're amending identifiers, ensure UTF8
    if (![[mySQLConnection encoding] hasPrefix:@"utf8"]) {
        [mySQLConnection setEncoding:@"utf8mb4"];
    }

    SPDatabaseAction *dbAction = [[SPDatabaseAction alloc] init];
    [dbAction setConnection:mySQLConnection];
    BOOL res = [dbAction createDatabase:[databaseNameField stringValue]
                           withEncoding:[addDatabaseCharsetHelper selectedCharset]
                              collation:[addDatabaseCharsetHelper selectedCollation]];

    if (!res) {
        // An error occurred
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error", @"error") message:[NSString stringWithFormat:NSLocalizedString(@"Couldn't create database.\nMySQL said: %@", @"message of panel when creation of db failed"), [mySQLConnection lastErrorMessage]] callback:nil];
        return;
    }

    // this refreshes the allDatabases array
    [self setDatabases];

    // inform observers that a new database was added
    [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:SPDatabaseCreatedRemovedRenamedNotification object:nil];

    // Select the database
    [self selectDatabase:[databaseNameField stringValue] item:nil];
}

/**
 * Run ALTER statement against current db.
 */
- (void)_alterDatabase {
    //we'll always run the alter statement, even if old == new because after all that is what the user requested

    NSString *newCharset   = [alterDatabaseCharsetHelper selectedCharset];
    NSString *newCollation = [alterDatabaseCharsetHelper selectedCollation];

    NSString *alterStatement = [NSString stringWithFormat:@"ALTER DATABASE %@ DEFAULT CHARACTER SET %@", [[self database] backtickQuotedString],[newCharset backtickQuotedString]];

    //technically there is an issue here: If a user had a non-default collation and now wants to switch to the default collation this cannot be specidifed (default == nil).
    //However if you just do an ALTER with CHARACTER SET == oldCharset MySQL will still reset the collation therefore doing exactly what we want.
    if(newCollation) {
        alterStatement = [NSString stringWithFormat:@"%@ DEFAULT COLLATE %@",alterStatement,[newCollation backtickQuotedString]];
    }

    //run alter
    [mySQLConnection queryString:alterStatement];

    if ([mySQLConnection queryErrored]) {
        // An error occurred
        [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error", @"error") message:[NSString stringWithFormat:NSLocalizedString(@"Couldn't alter database.\nMySQL said: %@", @"Alter Database : Query Failed ($1 = mysql error message)"), [mySQLConnection lastErrorMessage]] callback:nil];
        return;
    }

    //invalidate old cache values
    [databaseDataInstance resetAllData];
}

/**
 * Removes the current database.
 *
 * This method *MUST* be called from the UI thread!
 */
- (void)_removeDatabase
{
    // Drop the database from the server
    [mySQLConnection queryString:[NSString stringWithFormat:@"DROP DATABASE %@", [[self database] backtickQuotedString]]];

    if ([mySQLConnection queryErrored]) {
        // An error occurred
        [self performSelector:@selector(showErrorSheetWith:)
                   withObject:[NSArray arrayWithObjects:NSLocalizedString(@"Error", @"error"),
                               [NSString stringWithFormat:NSLocalizedString(@"Couldn't delete the database.\nMySQL said: %@", @"message of panel when deleting db failed"), [mySQLConnection lastErrorMessage]],
                               nil]
                   afterDelay:0.3];

        return;
    }

    // Remove db from navigator and completion list array,
    // do to threading we have to delete it from 'allDatabases' directly
    // before calling navigator
    [allDatabases removeObject:[self database]];

    // This only deletes the db and refreshes the navigator since nothing is changed
    // that's why we can run this on main thread
    [databaseStructureRetrieval queryDbStructureWithUserInfo:nil];

    [self setDatabases];

    [tablesListInstance setConnection:mySQLConnection];

    // inform observers that a database was dropped
    [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:SPDatabaseCreatedRemovedRenamedNotification object:nil];

    [self updateWindowTitle:self];
}

/**
 * Select the specified database and, optionally, table.
 */
- (void)_selectDatabaseAndItem:(NSDictionary *)selectionDetails
{
    @autoreleasepool {
        NSString *targetDatabaseName = [selectionDetails objectForKey:@"database"];
        NSString *targetItemName = [selectionDetails objectForKey:@"item"];

        // Save existing scroll position and details, and ensure no duplicate entries are created as table list changes
        BOOL historyStateChanging = [spHistoryControllerInstance modifyingState];

        if (!historyStateChanging) {
            [spHistoryControllerInstance updateHistoryEntries];
            [spHistoryControllerInstance setModifyingState:YES];
        }

        if (![targetDatabaseName isEqualToString:selectedDatabase]) {
            // Attempt to select the specified database, and abort on failure
            if ([[chooseDatabaseButton onMainThread] indexOfItemWithTitle:targetDatabaseName] == NSNotFound || ![mySQLConnection selectDatabase:targetDatabaseName])
            {
                // End the task first to ensure the database dropdown can be reselected
                [self endTask];

                if ([mySQLConnection isConnected]) {

                    // Update the database list
                    [[self onMainThread] setDatabases];

                    [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"Error", @"error") message:[NSString stringWithFormat:NSLocalizedString(@"Unable to select database %@.\nPlease check you have the necessary privileges to view the database, and that the database still exists.", @"message of panel when connection to db failed after selecting from popupbutton"), targetDatabaseName] callback:nil];
                }

                return;
            }

            [[chooseDatabaseButton onMainThread] selectItemWithTitle:targetDatabaseName];

            selectedDatabase = [[NSString alloc] initWithString:targetDatabaseName];
            selectedTableName = nil;

            [databaseDataInstance resetAllData];

            // Update the stored database encoding, used for views, "default" table encodings, and to allow
            // or disallow use of the "View using encoding" menu
            [self detectDatabaseEncoding];

            // Set the connection of SPTablesList to reload tables in db
            [tablesListInstance setConnection:mySQLConnection];

            // Update the window title
            [self updateWindowTitle:self];

            // Add a history entry
            if (!historyStateChanging) {
                [spHistoryControllerInstance setModifyingState:NO];
                [spHistoryControllerInstance updateHistoryEntries];
            }
        }

        SPMainQSync(^{
            BOOL focusOnFilter = YES;
            if (targetItemName) focusOnFilter = NO;

            // If a the table has changed, update the selection
            if (![targetItemName isEqualToString:[self table]] && targetItemName) {
                focusOnFilter = ![self->tablesListInstance selectItemWithName:targetItemName];
            }

            // Ensure the window focus is on the table list or the filter as appropriate
            [self->tablesListInstance setTableListSelectability:YES];
            if (focusOnFilter) {
                [self->tablesListInstance makeTableListFilterHaveFocus];
            } else {
                [self->tablesListInstance makeTableListHaveFocus];
            }
            [self->tablesListInstance setTableListSelectability:NO];
        });

        [self endTask];
        [self _processDatabaseChangedBundleTriggerActions];
    }
}

- (void)_processDatabaseChangedBundleTriggerActions
{
    NSArray __block *triggeredCommands = nil;

    dispatch_sync(dispatch_get_main_queue(), ^{
        triggeredCommands = [SPBundleManager.shared bundleCommandsForTrigger:SPBundleTriggerActionDatabaseChanged];
    });


    for (NSString* cmdPath in triggeredCommands)
    {
        NSArray *data = [cmdPath componentsSeparatedByString:@"|"];
        NSMenuItem *aMenuItem = [[NSMenuItem alloc] init];

        [aMenuItem setTag:0];
        [aMenuItem setToolTip:[data objectAtIndex:0]];

        // For HTML output check if corresponding window already exists
        BOOL stopTrigger = NO;

        if ([(NSString *)[data objectAtIndex:2] length]) {
            BOOL correspondingWindowFound = NO;
            NSString *uuid = [data objectAtIndex:2];

            for (id win in [NSApp windows])
            {
                if([[[[win delegate] class] description] isEqualToString:@"SPBundleHTMLOutputController"]) {
                    if([[[win delegate] windowUUID] isEqualToString:uuid]) {
                        correspondingWindowFound = YES;
                        break;
                    }
                }
            }

            if(!correspondingWindowFound) stopTrigger = YES;
        }
        if(!stopTrigger) {
            id firstResponder = [[NSApp keyWindow] firstResponder];
            if([[data objectAtIndex:1] isEqualToString:SPBundleScopeGeneral]) {
                [SPBundleManager.shared executeBundleItemForApp:aMenuItem];
            }
            else if([[data objectAtIndex:1] isEqualToString:SPBundleScopeDataTable]) {
                if ([[[firstResponder class] description] isEqualToString:@"SPCopyTable"]) {
                    [[firstResponder onMainThread] executeBundleItemForDataTable:aMenuItem];
                }
            }
            else if([[data objectAtIndex:1] isEqualToString:SPBundleScopeInputField]) {
                if ([firstResponder isKindOfClass:[NSTextView class]]) {
                    [[firstResponder onMainThread] executeBundleItemForInputField:aMenuItem];
                }
            }
        }
    }
}

/**
 * Add any necessary preference observers to allow live updating on changes.
 */
- (void)_addPreferenceObservers
{
    // Register observers for when the DisplayTableViewVerticalGridlines preference changes
    [prefs addObserver:self forKeyPath:SPDisplayTableViewVerticalGridlines options:NSKeyValueObservingOptionNew context:NULL];
    [prefs addObserver:tableSourceInstance forKeyPath:SPDisplayTableViewVerticalGridlines options:NSKeyValueObservingOptionNew context:NULL];
    [prefs addObserver:customQueryInstance forKeyPath:SPDisplayTableViewVerticalGridlines options:NSKeyValueObservingOptionNew context:NULL];
    [prefs addObserver:tableRelationsInstance forKeyPath:SPDisplayTableViewVerticalGridlines options:NSKeyValueObservingOptionNew context:NULL];
    [prefs addObserver:self forKeyPath:SPEditInSheetEnabled options:NSKeyValueObservingOptionNew context:NULL];
    [prefs addObserver:[SPQueryController sharedQueryController] forKeyPath:SPDisplayTableViewVerticalGridlines options:NSKeyValueObservingOptionNew context:NULL];

    // Register observers for when the logging preference changes
    [prefs addObserver:[SPQueryController sharedQueryController] forKeyPath:SPConsoleEnableLogging options:NSKeyValueObservingOptionNew context:NULL];

    // Register a second observer for when the logging preference changes so we can tell the current connection about it
    [prefs addObserver:self forKeyPath:SPConsoleEnableLogging options:NSKeyValueObservingOptionNew context:NULL];
}

/**
 * Remove any previously added preference observers.
 */
- (void)_removePreferenceObservers
{
    [prefs removeObserver:self forKeyPath:SPConsoleEnableLogging];
    [prefs removeObserver:self forKeyPath:SPEditInSheetEnabled];
    [prefs removeObserver:self forKeyPath:SPDisplayTableViewVerticalGridlines];

    [prefs removeObserver:customQueryInstance forKeyPath:SPDisplayTableViewVerticalGridlines];
    [prefs removeObserver:tableRelationsInstance forKeyPath:SPDisplayTableViewVerticalGridlines];
    [prefs removeObserver:tableSourceInstance forKeyPath:SPDisplayTableViewVerticalGridlines];

    [prefs removeObserver:[SPQueryController sharedQueryController] forKeyPath:SPConsoleEnableLogging];
    [prefs removeObserver:[SPQueryController sharedQueryController] forKeyPath:SPDisplayTableViewVerticalGridlines];
}

#pragma mark - SPDatabaseViewController

#pragma mark Getters

/**
 * Returns the master database view, containing the tables list and views for
 * table setup and contents.
 */
- (NSView *)databaseView
{
    return parentView;
}

/**
 * Returns the name of the currently selected table/view/procedure/function.
 */
- (NSString *)table
{
    return selectedTableName;
}

/**
 * Returns the currently selected table type, or -1 if no table or multiple tables are selected
 */
- (SPTableType)tableType
{
    return selectedTableType;
}

/**
 * Returns YES if table source has already been loaded
 */
- (BOOL)structureLoaded
{
    return structureLoaded;
}

/**
 * Returns YES if table content has already been loaded
 */
- (BOOL)contentLoaded
{
    return contentLoaded;
}

/**
 * Returns YES if table status has already been loaded
 */
- (BOOL)statusLoaded
{
    return statusLoaded;
}

#pragma mark -
#pragma mark Tab view control and delegate methods

//WARNING: Might be called from code in background threads
- (void)viewStructure {

    SPMainQSync(^{
        // Cancel the selection if currently editing a view and unable to save
        if (![self couldCommitCurrentViewActions]) {
            [self.mainToolbar setSelectedItemIdentifier:*SPViewModeToMainToolbarMap[[self->prefs integerForKey:SPLastViewMode]]];
            return;
        }

        [self->tableTabView selectTabViewItemAtIndex:0];
        [self.mainToolbar setSelectedItemIdentifier:SPMainToolbarTableStructure];
        [self->spHistoryControllerInstance updateHistoryEntries];

        [self->prefs setInteger:SPStructureViewMode forKey:SPLastViewMode];

    });
}

- (void)viewContent {
    SPMainQSync(^{
        // Cancel the selection if currently editing a view and unable to save
        if (![self couldCommitCurrentViewActions]) {
            [self.mainToolbar setSelectedItemIdentifier:*SPViewModeToMainToolbarMap[[self->prefs integerForKey:SPLastViewMode]]];
            return;
        }

        [self->tableTabView selectTabViewItemAtIndex:1];
        [self.mainToolbar setSelectedItemIdentifier:SPMainToolbarTableContent];
        [self->spHistoryControllerInstance updateHistoryEntries];
        [self->prefs setInteger:SPContentViewMode forKey:SPLastViewMode];
    });
}

- (void)viewQuery {
    SPMainQSync(^{
        // Cancel the selection if currently editing a view and unable to save
        if (![self couldCommitCurrentViewActions]) {
            [self.mainToolbar setSelectedItemIdentifier:*SPViewModeToMainToolbarMap[[self->prefs integerForKey:SPLastViewMode]]];
            return;
        }

        [self->tableTabView selectTabViewItemAtIndex:2];
        [self.mainToolbar setSelectedItemIdentifier:SPMainToolbarCustomQuery];
        [self->spHistoryControllerInstance updateHistoryEntries];

        // Set the focus on the text field
        [[self.parentWindowController window] makeFirstResponder:self->customQueryTextView];

        [self->prefs setInteger:SPQueryEditorViewMode forKey:SPLastViewMode];
    });

}

- (void)viewStatus {
    SPMainQSync(^{
        // Cancel the selection if currently editing a view and unable to save
        if (![self couldCommitCurrentViewActions]) {
            [self.mainToolbar setSelectedItemIdentifier:*SPViewModeToMainToolbarMap[[self->prefs integerForKey:SPLastViewMode]]];
            return;
        }

        [self->tableTabView selectTabViewItemAtIndex:3];
        [self.mainToolbar setSelectedItemIdentifier:SPMainToolbarTableInfo];
        [self->spHistoryControllerInstance updateHistoryEntries];

        if ([[self table] length]) {
            [self->extendedTableInfoInstance loadTable:[self table]];
        }

        [[self.parentWindowController window] makeFirstResponder:[self->extendedTableInfoInstance valueForKeyPath:@"tableCreateSyntaxTextView"]];

        [self->prefs setInteger:SPTableInfoViewMode forKey:SPLastViewMode];
    });

}

- (void)viewRelations {
    SPMainQSync(^{
        // Cancel the selection if currently editing a view and unable to save
        if (![self couldCommitCurrentViewActions]) {
            [self.mainToolbar setSelectedItemIdentifier:*SPViewModeToMainToolbarMap[[self->prefs integerForKey:SPLastViewMode]]];
            return;
        }

        [self->tableTabView selectTabViewItemAtIndex:4];
        [self.mainToolbar setSelectedItemIdentifier:SPMainToolbarTableRelations];
        [self->spHistoryControllerInstance updateHistoryEntries];

        [self->prefs setInteger:SPRelationsViewMode forKey:SPLastViewMode];
    });

}

- (void)viewTriggers {
    SPMainQSync(^{
        // Cancel the selection if currently editing a view and unable to save
        if (![self couldCommitCurrentViewActions]) {
            [self.mainToolbar setSelectedItemIdentifier:*SPViewModeToMainToolbarMap[[self->prefs integerForKey:SPLastViewMode]]];
            return;
        }

        [self->tableTabView selectTabViewItemAtIndex:5];
        [self.mainToolbar setSelectedItemIdentifier:SPMainToolbarTableTriggers];
        [self->spHistoryControllerInstance updateHistoryEntries];

        [self->prefs setInteger:SPTriggersViewMode forKey:SPLastViewMode];
    });
}

/**
 * Mark the structure tab for refresh when it's next switched to,
 * or reload the view if it's currently active
 */
- (void)setStructureRequiresReload:(BOOL)reload
{
    BOOL reloadRequired = reload;

    if ([self currentlySelectedView] == SPTableViewStructure) {
        reloadRequired = NO;
    }

    if (reloadRequired && selectedTableName) {
        [tableSourceInstance loadTable:selectedTableName];
    }
    else {
        structureLoaded = !reload;
    }
}

/**
 * Mark the content tab for refresh when it's next switched to,
 * or reload the view if it's currently active
 */
- (void)setContentRequiresReload:(BOOL)reload
{
    if (reload && selectedTableName
        && [self currentlySelectedView] == SPTableViewContent
        ) {
        [tableContentInstance loadTable:selectedTableName];
    }
    else {
        contentLoaded = !reload;
    }
}

/**
 * Mark the extended tab info for refresh when it's next switched to,
 * or reload the view if it's currently active
 */
- (void)setStatusRequiresReload:(BOOL)reload
{
    if (reload && selectedTableName
        && [self currentlySelectedView] == SPTableViewStatus
        ) {
        [[extendedTableInfoInstance onMainThread] loadTable:selectedTableName];
    }
    else {
        statusLoaded = !reload;
    }
}

/**
 * Mark the relations tab for refresh when it's next switched to,
 * or reload the view if it's currently active
 */
- (void)setRelationsRequiresReload:(BOOL)reload
{
    if (reload && selectedTableName
        && [self currentlySelectedView] == SPTableViewRelations
        ) {
        [[tableRelationsInstance onMainThread] refreshRelations:self];
    }
    else {
        relationsLoaded = !reload;
    }
}

/**
 * Triggers a task to update the newly selected tab view, ensuring
 * the data is fully loaded and up-to-date.
 */
- (void)tabView:(NSTabView *)aTabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    [self startTaskWithDescription:[NSString stringWithFormat:NSLocalizedString(@"Loading %@...", @"Loading table task string"), [self table]]];

    // We can't pass aTabView or tabViewItem UI objects to a bg thread, but since the change should already
    // be done in *did*SelectTabViewItem we can just ask the tab view for the current selection index and use that
    SPTableViewType newView = [self currentlySelectedView];

    if ([NSThread isMainThread]) {
        [NSThread detachNewThreadWithName:SPCtxt(@"SPDatabaseDocument view load task", self)
                                   target:self
                                 selector:@selector(_loadTabTask:)
                                   object:@(newView)];
    }
    else {
        [self _loadTabTask:@(newView)];
    }
}

#pragma mark -
#pragma mark Table control

/**
 * Loads a specified table into the database view, and ensures it's selected in
 * the tables list.  Passing a table name of nil will deselect any currently selected
 * table, but will leave multiple selections intact.
 * If this method is supplied with the currently selected name, a reload rather than
 * a load will be triggered.
 */
- (void)loadTable:(NSString *)aTable ofType:(SPTableType)aTableType
{
    // Ensure a connection is still present
    if (![mySQLConnection isConnected]){
        SPLog(@"![mySQLConnection isConnected], returning");
        return;
    }

    // If the supplied table name was nil, clear the views.
    if (!aTable) {

        // Update the selected table name and type


        selectedTableType = SPTableTypeNone;

        // Clear the views
        [[tablesListInstance onMainThread] setSelectionState:nil];
        [tableSourceInstance loadTable:nil];
        [tableContentInstance loadTable:nil];
        [[extendedTableInfoInstance onMainThread] loadTable:nil];
        [[tableTriggersInstance onMainThread] resetInterface];
        [[tableRelationsInstance onMainThread] refreshRelations:self];
        structureLoaded = NO;
        contentLoaded = NO;
        statusLoaded = NO;
        triggersLoaded = NO;
        relationsLoaded = NO;

        // Update the window title
        [self updateWindowTitle:self];

        // Add a history entry
        [spHistoryControllerInstance updateHistoryEntries];

        // Notify listeners of the table change
        [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:SPTableChangedNotification object:self];

        return;
    }

    BOOL isReloading = (selectedTableName && [selectedTableName isEqualToString:aTable]);

    // Store the new name

    selectedTableName = [[NSString alloc] initWithString:aTable];
    selectedTableType = aTableType;

    // Start a task
    if (isReloading) {
        [self startTaskWithDescription:NSLocalizedString(@"Reloading...", @"Reloading table task string")];
    }
    else {
        [self startTaskWithDescription:[NSString stringWithFormat:NSLocalizedString(@"Loading %@...", @"Loading table task string"), aTable]];
    }

    // Update the tables list interface - also updates menus to reflect the selected table type
    [[tablesListInstance onMainThread] setSelectionState:[NSDictionary dictionaryWithObjectsAndKeys:aTable, @"name", [NSNumber numberWithInteger:aTableType], @"type", nil]];

    // If on the main thread, fire up a thread to deal with view changes and data loading;
    // if already on a background thread, make the changes on the existing thread.
    if ([NSThread isMainThread]) {
        [NSThread detachNewThreadWithName:SPCtxt(@"SPDatabaseDocument table load task", self)
                                   target:self
                                 selector:@selector(_loadTableTask)
                                   object:nil];
    }
    else {
        [self _loadTableTask];
    }
}

/**
 * In a threaded task, ensure that the supplied tab is loaded -
 * usually as a result of switching to it.
 */
- (void)_loadTabTask:(NSNumber *)tabViewItemIndexNumber
{
    @autoreleasepool {
        // If anything other than a single table or view is selected, don't proceed.
        if (![self table] || ([tablesListInstance tableType] != SPTableTypeTable && [tablesListInstance tableType] != SPTableTypeView)) {
            [self endTask];
            return;
        }

        // Get the tab view index and ensure the associated view is loaded
        SPTableViewType selectedTabViewIndex = (SPTableViewType)[tabViewItemIndexNumber integerValue];

        switch (selectedTabViewIndex) {
            case SPTableViewStructure:
                if (!structureLoaded) {
                    [tableSourceInstance loadTable:selectedTableName];
                    structureLoaded = YES;
                }
                break;
            case SPTableViewContent:
                if (!contentLoaded) {
                    [tableContentInstance loadTable:selectedTableName];
                    contentLoaded = YES;
                }
                break;
            case SPTableViewStatus:
                if (!statusLoaded) {
                    [[extendedTableInfoInstance onMainThread] loadTable:selectedTableName];
                    statusLoaded = YES;
                }
                break;
            case SPTableViewTriggers:
                if (!triggersLoaded) {
                    [[tableTriggersInstance onMainThread] loadTriggers];
                    triggersLoaded = YES;
                }
                break;
            case SPTableViewRelations:
                if (!relationsLoaded) {
                    [[tableRelationsInstance onMainThread] refreshRelations:self];
                    relationsLoaded = YES;
                }
                break;
            case SPTableViewCustomQuery:
            case SPTableViewInvalid:
                break;
        }

        [self endTask];
    }
}

/**
 * In a threaded task, load the currently selected table/view/proc/function.
 */
- (void)_loadTableTask
{
    @autoreleasepool {
        NSString *tableEncoding = nil;

        // Update the window title
        [self updateWindowTitle:self];

        // Reset table information caches and mark that all loaded views require their data reloading
        [tableDataInstance resetAllData];

        structureLoaded = NO;
        contentLoaded = NO;
        statusLoaded = NO;
        triggersLoaded = NO;
        relationsLoaded = NO;

        // Ensure status and details are fetched using UTF8
        NSString *previousEncoding = [mySQLConnection encoding];
        BOOL changeEncoding = ![previousEncoding hasPrefix:@"utf8"];

        if (changeEncoding) {
            [mySQLConnection storeEncodingForRestoration];
            [mySQLConnection setEncoding:@"utf8mb4"];
        }

        // Cache status information on the working thread
        [tableDataInstance updateStatusInformationForCurrentTable];

        // Check the current encoding against the table encoding to see whether
        // an encoding change and reset is required.  This also caches table information on
        // the working thread.
        if( selectedTableType == SPTableTypeView || selectedTableType == SPTableTypeTable) {

            // tableEncoding == nil indicates that there was an error while retrieving table data
            tableEncoding = [tableDataInstance tableEncoding];

            // If encoding is set to Autodetect, update the connection character set encoding to utf8mb4
            // This allows us to receive data encoded in various charsets as UTF-8 characters.
            if ([[prefs objectForKey:SPDefaultEncoding] intValue] == SPEncodingAutodetect) {
                if (![@"utf8mb4" isEqualToString:previousEncoding]) {
                    [self setConnectionEncoding:@"utf8mb4" reloadingViews:NO];
                    changeEncoding = NO;
                }
            }
        }

        if (changeEncoding) [mySQLConnection restoreStoredEncoding];

        // Notify listeners of the table change now that the state is fully set up.
        [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:SPTableChangedNotification object:self];

        // Restore view states as appropriate
        [spHistoryControllerInstance restoreViewStates];

        // Load the currently selected view if looking at a table or view
        if (tableEncoding && (selectedTableType == SPTableTypeView || selectedTableType == SPTableTypeTable))
        {
            NSInteger selectedTabViewIndex = [[self onMainThread] currentlySelectedView];

            switch (selectedTabViewIndex) {
                case SPTableViewStructure:
                    [tableSourceInstance loadTable:selectedTableName];
                    structureLoaded = YES;
                    break;
                case SPTableViewContent:
                    [tableContentInstance loadTable:selectedTableName];
                    contentLoaded = YES;
                    break;
                case SPTableViewStatus:
                    [[extendedTableInfoInstance onMainThread] loadTable:selectedTableName];
                    statusLoaded = YES;
                    break;
                case SPTableViewTriggers:
                    [[tableTriggersInstance onMainThread] loadTriggers];
                    triggersLoaded = YES;
                    break;
                case SPTableViewRelations:
                    [[tableRelationsInstance onMainThread] refreshRelations:self];
                    relationsLoaded = YES;
                    break;
            }
        }

        // Clear any views which haven't been loaded as they weren't visible.  Note
        // that this should be done after reloading visible views, instead of clearing all
        // views, to reduce UI operations and avoid resetting state unnecessarily.
        // Some views (eg TableRelations) make use of the SPTableChangedNotification and
        // so don't require manual clearing.
        if (!structureLoaded) [tableSourceInstance loadTable:nil];
        if (!contentLoaded) [tableContentInstance loadTable:nil];
        if (!statusLoaded) [[extendedTableInfoInstance onMainThread] loadTable:nil];
        if (!triggersLoaded) [[tableTriggersInstance onMainThread] resetInterface];

        // If the table row counts an inaccurate and require updating, trigger an update - no
        // action will be performed if not necessary
        [tableDataInstance updateAccurateNumberOfRowsForCurrentTableForcingUpdate:NO];

        SPMainQSync(^{
            // Update the "Show Create Syntax" window if it's already opened
            // according to the selected table/view/proc/func
            if ([[self getCreateTableSyntaxWindow] isVisible]) {
                [self showCreateTableSyntax:self];
            }
        });

        // Add a history entry
        @synchronized(self) {
            [spHistoryControllerInstance updateHistoryEntries];
        }
        // Empty the loading pool and exit the thread
        [self endTask];

        NSArray __block *triggeredCommands = nil;

        dispatch_sync(dispatch_get_main_queue(), ^{
            triggeredCommands = [SPBundleManager.shared bundleCommandsForTrigger:SPBundleTriggerActionTableChanged];
        });

        for(NSString* cmdPath in triggeredCommands)
        {
            NSArray *data = [cmdPath componentsSeparatedByString:@"|"];
            NSMenuItem *aMenuItem = [[NSMenuItem alloc] init];
            [aMenuItem setTag:0];
            [aMenuItem setToolTip:[data objectAtIndex:0]];

            // For HTML output check if corresponding window already exists
            BOOL stopTrigger = NO;
            if([(NSString*)[data objectAtIndex:2] length]) {
                BOOL correspondingWindowFound = NO;
                NSString *uuid = [data objectAtIndex:2];
                for(id win in [NSApp windows]) {
                    if([[[[win delegate] class] description] isEqualToString:@"SPBundleHTMLOutputController"]) {
                        if([[[win delegate] windowUUID] isEqualToString:uuid]) {
                            correspondingWindowFound = YES;
                            break;
                        }
                    }
                }
                if(!correspondingWindowFound) stopTrigger = YES;
            }
            if(!stopTrigger) {
                id firstResponder = [[NSApp keyWindow] firstResponder];
                if([[data objectAtIndex:1] isEqualToString:SPBundleScopeGeneral]) {
                    [SPBundleManager.shared executeBundleItemForApp:aMenuItem];
                }
                else if([[data objectAtIndex:1] isEqualToString:SPBundleScopeDataTable]) {
                    if([[[firstResponder class] description] isEqualToString:@"SPCopyTable"])
                        [[firstResponder onMainThread] executeBundleItemForDataTable:aMenuItem];
                }
                else if([[data objectAtIndex:1] isEqualToString:SPBundleScopeInputField]) {
                    if([firstResponder isKindOfClass:[NSTextView class]])
                        [[firstResponder onMainThread] executeBundleItemForInputField:aMenuItem];
                }
            }
        }
    }
}

#pragma mark - SPMySQLConnection delegate methods

/**
 * Invoked when the framework is about to perform a query.
 */
- (void)willQueryString:(NSString *)query connection:(id)connection
{
    if ([prefs boolForKey:SPConsoleEnableLogging]) {
        if ((_queryMode == SPInterfaceQueryMode && [prefs boolForKey:SPConsoleEnableInterfaceLogging]) ||
            (_queryMode == SPCustomQueryQueryMode && [prefs boolForKey:SPConsoleEnableCustomQueryLogging]) ||
            (_queryMode == SPImportExportQueryMode && [prefs boolForKey:SPConsoleEnableImportExportLogging]))
        {
            [[SPQueryController sharedQueryController] showMessageInConsole:query connection:[self name] database:[self database]];
        }
    }
}

/**
 * Invoked when the query just executed by the framework resulted in an error.
 */
- (void)queryGaveError:(NSString *)error connection:(id)connection
{
    if ([prefs boolForKey:SPConsoleEnableLogging] && [prefs boolForKey:SPConsoleEnableErrorLogging]) {
        [[SPQueryController sharedQueryController] showErrorInConsole:error connection:[self name] database:[self database]];
    }
}

/**
 * Invoked when the current connection needs a password from the Keychain.
 */
- (NSString *)keychainPasswordForConnection:(SPMySQLConnection *)connection
{
    return [connectionController keychainPassword];
}

/**
 * Invoked when the current connection needs a ssh password from the Keychain.
 * This isn't actually part of the SPMySQLConnection delegate protocol, but is here
 * due to its similarity to the previous method.
 */
- (NSString *)keychainPasswordForSSHConnection:(SPMySQLConnection *)connection
{
    // If no keychain item is available, return an empty password
    NSString *password = [connectionController keychainPasswordForSSH];
    if (!password) return @"";

    return password;
}

/**
 * Invoked when an attempt was made to execute a query on the current connection, but the connection is not
 * actually active.
 */
- (void)noConnectionAvailable:(id)connection
{
    [NSAlert createWarningAlertWithTitle:NSLocalizedString(@"No connection available", @"no connection available message") message:NSLocalizedString(@"An error has occurred and there doesn't seem to be a connection available.", @"no connection available informatie message") callback:nil];
}

/**
 * Invoked when the connection fails and the framework needs to know how to proceed.
 */
- (SPMySQLConnectionLostDecision)connectionLost:(id)connection
{

    SPLog(@"connectionLost");

    SPMySQLConnectionLostDecision connectionErrorCode = SPMySQLConnectionLostDisconnect;

    // Only display the reconnect dialog if the window is visible
    // and we are not terminating
    if ([self.parentWindowController window] && [[self.parentWindowController window] isVisible] && appIsTerminating == NO) {

        SPLog(@"not terminating, parentWindow isVisible, showing connectionErrorDialog");
        // Ensure the window isn't miniaturized
        if ([[self.parentWindowController window] isMiniaturized]) {
            [[self.parentWindowController window] deminiaturize:self];
        }
        [[self parentWindowControllerWindow] orderWindow:NSWindowAbove relativeTo:0];

        // Display the connection error dialog and wait for the return code
        [[self.parentWindowController window] beginSheet:connectionErrorDialog completionHandler:nil];
        connectionErrorCode = (SPMySQLConnectionLostDecision)[NSApp runModalForWindow:connectionErrorDialog];

        [NSApp endSheet:connectionErrorDialog];
        [connectionErrorDialog orderOut:nil];

        queryStartDate = [[NSDate alloc] init];

        // If 'disconnect' was selected, trigger a window close.
        if (connectionErrorCode == SPMySQLConnectionLostDisconnect) {
            [self performSelectorOnMainThread:@selector(closeAndDisconnect) withObject:nil waitUntilDone:YES];
        }
    }

    return connectionErrorCode;
}

/**
 * Invoke to display an informative but non-fatal error directly to the user.
 */
- (void)showErrorWithTitle:(NSString *)theTitle message:(NSString *)theMessage
{
    SPMainQSync(^{
        if ([[self.parentWindowController window] isVisible]) {
            [NSAlert createWarningAlertWithTitle:theTitle message:theMessage callback:nil];
        }
    });
}

/**
 * Invoked when user dismisses the error sheet displayed as a result of the current connection being lost.
 */
- (IBAction)closeErrorConnectionSheet:(id)sender
{
    [NSApp stopModalWithCode:[sender tag]];
}

/**
 * Close the connection - should be performed on the main thread.
 */
- (void)closeAndDisconnect {

    _isConnected = NO;

    [self.parentWindowControllerWindow orderOut:self];
    [self.parentWindowControllerWindow setAlphaValue:0.0f];
    [self.parentWindowControllerWindow performSelector:@selector(close) withObject:nil afterDelay:1.0];

    // if tab closed and there is text in the query view, safe to history
    NSString *queryString = [self->customQueryTextView.textStorage string];

    if([queryString length] > 0){
        [[SPQueryController sharedQueryController] addHistory:queryString forFileURL:[self fileURL]];
    }

    // Cancel autocompletion trigger
    if([prefs boolForKey:SPCustomQueryAutoComplete]) {
        [NSObject cancelPreviousPerformRequestsWithTarget:[customQueryInstance valueForKeyPath:@"textView"]
                                                 selector:@selector(doAutoCompletion)
                                                   object:nil];
    }
    if([prefs boolForKey:SPCustomQueryUpdateAutoHelp]) {
        [NSObject cancelPreviousPerformRequestsWithTarget:[customQueryInstance valueForKeyPath:@"textView"]
                                                 selector:@selector(autoHelp)
                                                   object:nil];
    }

    if (_isConnected) {
        [self closeConnection];
    } else {
        [connectionController cancelConnection:self];
    }
    if ([[[SPQueryController sharedQueryController] window] isVisible]) [self toggleConsole];
    [createTableSyntaxWindow orderOut:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSWindow *)parentWindowControllerWindow {
    return [self.parentWindowController window];
}

#pragma mark - SPPrintController

/**
 * WebView delegate method.
 */
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {


    NSPrintOperation *op = [SPPrintUtility preparePrintOperationWithView:[[[printWebView mainFrame] frameView] documentView] printView:printWebView];

    /* -endTask has to be called first, since the toolbar caches the item enabled state before starting a sheet,
     * disables all items and restores the cached state after the sheet ends. Because the database chooser is disabled
     * during tasks, launching the sheet before calling -endTask first would result in the following flow:
     * - toolbar item caches database chooser state as disabled (because of the active task)
     * - sheet is shown
     * - endTask reenables database chooser (has no effect because of the open sheet)
     * - user dismisses sheet after some time
     * - toolbar item restores cached state and disables database chooser again
     * => Inconsistent UI: database chooser disabled when it should actually be enabled
     */
    if ([self isWorking]) [self endTask];

    [op runOperationModalForWindow:[self.parentWindowController window] delegate:self didRunSelector:nil contextInfo:nil];
}

/**
 * Loads the print document interface. The actual printing is done in the doneLoading delegate.
 */
- (void)printDocument {
    // Only display warning for the 'Table Content' view
    if ([self currentlySelectedView] == SPTableViewContent) {

        NSInteger rowLimit = [prefs integerForKey:SPPrintWarningRowLimit];

        // Result count minus one because the first element is the column names
        NSInteger resultRows = ([[tableContentInstance currentResult] count] - 1);

        if (resultRows > rowLimit) {

            NSString *message = [NSString stringWithFormat:NSLocalizedString(@"Are you sure you want to print the current content view of the table '%@'?\n\nIt currently contains %@ rows, which may take a significant amount of time to print.", @"continue to print informative message"), [self table], [NSNumberFormatter.decimalStyleFormatter stringFromNumber:[NSNumber numberWithLongLong:resultRows]]];
            [NSAlert createDefaultAlertWithTitle:NSLocalizedString(@"Continue to print?", @"continue to print message") message:message primaryButtonTitle:NSLocalizedString(@"Print", @"print button") primaryButtonHandler:^{
                [self startPrintDocumentOperation];
            } cancelButtonHandler:nil];
            return;
        }
    }

    [self startPrintDocumentOperation];
}

/**
 * Starts tge print document operation by spawning a new thread if required.
 */
- (void)startPrintDocumentOperation
{
    [self startTaskWithDescription:NSLocalizedString(@"Generating print document...", @"generating print document status message")];

    BOOL isTableInformation = ([self currentlySelectedView] == SPTableViewStatus);

    if ([NSThread isMainThread]) {
        printThread = [[NSThread alloc] initWithTarget:self selector:(isTableInformation) ? @selector(generateTableInfoHTMLForPrinting) : @selector(generateHTMLForPrinting) object:nil];
        [printThread setName:@"SPDatabaseDocument document generator"];

        [self enableTaskCancellationWithTitle:NSLocalizedString(@"Cancel", @"cancel button") callbackObject:self callbackFunction:@selector(generateHTMLForPrintingCallback)];

        [printThread start];
    }
    else {
        (isTableInformation) ? [self generateTableInfoHTMLForPrinting] : [self generateHTMLForPrinting];
    }
}

/**
 * HTML generation thread callback method.
 */
- (void)generateHTMLForPrintingCallback
{
    [self setTaskDescription:NSLocalizedString(@"Cancelling...", @"cancelling task status message")];

    // Cancel the print thread
    [printThread cancel];
}

/**
 * Loads the supplied HTML string in the print WebView.
 */
- (void)loadPrintWebViewWithHTMLString:(NSString *)HTMLString
{
    [[printWebView mainFrame] loadHTMLString:HTMLString baseURL:nil];


}

/**
 * Generates the HTML for the current view that is being printed.
 */
- (void)generateHTMLForPrinting
{
    @autoreleasepool {
        NSMutableDictionary *connection = [NSMutableDictionary dictionary];
        NSMutableDictionary *printData = [NSMutableDictionary dictionary];

        SPMainQSync(^{
            [connection setDictionary:[self connectionInformation]];
            [printData setObject:[self columnNames] forKey:@"columns"];
            SPTableViewType view = [self currentlySelectedView];

            NSString *heading = @"";

            // Table source view
            if (view == SPTableViewStructure) {

                NSDictionary *tableSource = [self->tableSourceInstance tableSourceForPrinting];

                NSInteger tableType = [self->tablesListInstance tableType];

                switch (tableType) {
                    case SPTableTypeTable:
                        heading = NSLocalizedString(@"Table Structure", @"table structure print heading");
                        break;
                    case SPTableTypeView:
                        heading = NSLocalizedString(@"View Structure", @"view structure print heading");
                        break;
                }

                NSArray *rows = [[NSArray alloc] initWithArray:
                                 [[tableSource objectForKey:@"structure"] objectsAtIndexes:
                                  [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, [[tableSource objectForKey:@"structure"] count] - 1)]]
                                 ];

                NSArray *indexes = [[NSArray alloc] initWithArray:
                                    [[tableSource objectForKey:@"indexes"] objectsAtIndexes:
                                     [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, [[tableSource objectForKey:@"indexes"] count] - 1)]]
                                    ];

                NSArray *indexColumns = [[tableSource objectForKey:@"indexes"] objectAtIndex:0];

                [printData setObject:rows forKey:@"rows"];
                [printData setObject:indexes forKey:@"indexes"];
                [printData setObject:indexColumns forKey:@"indexColumns"];

                if ([indexes count]) [printData setObject:@1 forKey:@"hasIndexes"];
            }
            // Table content view
            else if (view == SPTableViewContent) {

                NSArray *data = [self->tableContentInstance currentDataResultWithNULLs:NO hideBLOBs:YES];

                heading = NSLocalizedString(@"Table Content", @"table content print heading");

                NSArray *rows = [[NSArray alloc] initWithArray:
                                 [data objectsAtIndexes:
                                  [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, [data count] - 1)]]
                                 ];

                [printData setObject:rows forKey:@"rows"];
                [connection setValue:[self->tableContentInstance usedQuery] forKey:@"query"];
            }
            // Custom query view
            else if (view == SPTableViewCustomQuery) {

                NSArray *data = [self->customQueryInstance currentResult];

                heading = NSLocalizedString(@"Query Result", @"query result print heading");

                NSArray *rows = [[NSArray alloc] initWithArray:
                                 [data objectsAtIndexes:
                                  [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, [data count] - 1)]]
                                 ];

                [printData setObject:rows forKey:@"rows"];
                [connection setValue:[self->customQueryInstance usedQuery] forKey:@"query"];
            }
            // Table relations view
            else if (view == SPTableViewRelations) {

                NSArray *data = [self->tableRelationsInstance relationDataForPrinting];

                heading = NSLocalizedString(@"Table Relations", @"toolbar item label for switching to the Table Relations tab");

                NSArray *rows = [[NSArray alloc] initWithArray:
                                 [data objectsAtIndexes:
                                  [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, ([data count] - 1))]]
                                 ];

                [printData setObject:rows forKey:@"rows"];
            }
            // Table triggers view
            else if (view == SPTableViewTriggers) {

                NSArray *data = [self->tableTriggersInstance triggerDataForPrinting];

                heading = NSLocalizedString(@"Table Triggers", @"toolbar item label for switching to the Table Triggers tab");

                NSArray *rows = [[NSArray alloc] initWithArray:
                                 [data objectsAtIndexes:
                                  [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, ([data count] - 1))]]
                                 ];

                [printData setObject:rows forKey:@"rows"];
            }

            [printData setObject:heading forKey:@"heading"];
        });

        // Set up template engine with your chosen matcher
        MGTemplateEngine *engine = [MGTemplateEngine templateEngine];

        [engine setMatcher:[ICUTemplateMatcher matcherWithTemplateEngine:engine]];

        [engine setObject:connection forKey:@"c"];

        [printData setObject:@"Lucida Grande" forKey:@"font"];
        [printData setObject:([prefs boolForKey:SPDisplayTableViewVerticalGridlines]) ? @"1px solid #CCCCCC" : @"none" forKey:@"gridlines"];

        NSString *HTMLString = [engine processTemplateInFileAtPath:[[NSBundle mainBundle] pathForResource:SPHTMLPrintTemplate ofType:@"html"] withVariables:printData];

        // Check if the operation has been cancelled
        if ((printThread != nil) && (![NSThread isMainThread]) && ([printThread isCancelled])) {
            [self endTask];
            return;
        }

        [self performSelectorOnMainThread:@selector(loadPrintWebViewWithHTMLString:) withObject:HTMLString waitUntilDone:NO];
    }
}

/**
 * Generates the HTML for the table information view that is to be printed.
 */
- (void)generateTableInfoHTMLForPrinting
{
    @autoreleasepool {
        // Set up template engine with your chosen matcher
        MGTemplateEngine *engine = [MGTemplateEngine templateEngine];

        [engine setMatcher:[ICUTemplateMatcher matcherWithTemplateEngine:engine]];

        NSMutableDictionary *connection = [self connectionInformation];
        NSMutableDictionary *printData = [NSMutableDictionary dictionary];

        NSString *heading = NSLocalizedString(@"Table Information", @"table information print heading");

        [engine setObject:connection forKey:@"c"];
        [engine setObject:[[extendedTableInfoInstance onMainThread] tableInformationForPrinting] forKey:@"i"];

        [printData setObject:heading forKey:@"heading"];
        [printData setObject:[[NSUnarchiver unarchiveObjectWithData:[prefs objectForKey:SPCustomQueryEditorFont]] fontName] forKey:@"font"];

        NSString *HTMLString = [engine processTemplateInFileAtPath:[[NSBundle mainBundle] pathForResource:SPHTMLTableInfoPrintTemplate ofType:@"html"] withVariables:printData];

        // Check if the operation has been cancelled
        if ((printThread != nil) && (![NSThread isMainThread]) && ([printThread isCancelled])) {
            [self endTask];
            return;
        }

        [self performSelectorOnMainThread:@selector(loadPrintWebViewWithHTMLString:) withObject:HTMLString waitUntilDone:NO];
    }
}

/**
 * Returns an array of columns for whichever view is being printed.
 *
 * MUST BE CALLED ON THE UI THREAD!
 */
- (NSArray *)columnNames
{
    NSArray *columns = nil;

    SPTableViewType view = [self currentlySelectedView];

    // Table source view
    if ((view == SPTableViewStructure) && ([[tableSourceInstance tableSourceForPrinting] count] > 0)) {

        columns = [[NSArray alloc] initWithArray:[[[tableSourceInstance tableSourceForPrinting] objectForKey:@"structure"] objectAtIndex:0] copyItems:YES];
    }
    // Table content view
    else if ((view == SPTableViewContent) && ([[tableContentInstance currentResult] count] > 0)) {

        columns = [[NSArray alloc] initWithArray:[[tableContentInstance currentResult] objectAtIndex:0] copyItems:YES];
    }
    // Custom query view
    else if ((view == SPTableViewCustomQuery) && ([[customQueryInstance currentResult] count] > 0)) {

        columns = [[NSArray alloc] initWithArray:[[customQueryInstance currentResult] objectAtIndex:0] copyItems:YES];
    }
    // Table relations view
    else if ((view == SPTableViewRelations) && ([[tableRelationsInstance relationDataForPrinting] count] > 0)) {

        columns = [[NSArray alloc] initWithArray:[[tableRelationsInstance relationDataForPrinting] objectAtIndex:0] copyItems:YES];
    }
    // Table triggers view
    else if ((view == SPTableViewTriggers) && ([[tableTriggersInstance triggerDataForPrinting] count] > 0)) {

        columns = [[NSArray alloc] initWithArray:[[tableTriggersInstance triggerDataForPrinting] objectAtIndex:0] copyItems:YES];
    }

    return columns;
}

/**
 * Generates a dictionary of connection information that is used for printing.
 */
- (NSMutableDictionary *)connectionInformation
{
    NSDictionary *infoDict = [[NSBundle mainBundle] infoDictionary];
    NSString *versionForPrint = [NSString stringWithFormat:@"%@ %@ (%@ %@)",
                                 [infoDict objectForKey:@"CFBundleName"],
                                 [infoDict objectForKey:@"CFBundleShortVersionString"],
                                 NSLocalizedString(@"build", @"build label"),
                                 [infoDict objectForKey:@"CFBundleVersion"]];

    NSMutableDictionary *connection = [NSMutableDictionary dictionary];

    if ([[self user] length]) {
        [connection setValue:[self user] forKey:@"username"];
    }

    if ([[self table] length]) {
        [connection setValue:[self table] forKey:@"table"];
    }

    if ([connectionController port] && [[connectionController port] length]) {
        [connection setValue:[connectionController port] forKey:@"port"];
    }

    [connection setValue:[self host] forKey:@"hostname"];
    [connection setValue:selectedDatabase forKey:@"database"];
    [connection setValue:versionForPrint forKey:@"version"];

    return connection;
}

- (void)documentWillClose:(NSNotification *)notification {
    if ([notification.object isKindOfClass:[SPDatabaseDocument class]]) {
        SPDatabaseDocument *document = (SPDatabaseDocument *)[notification object];
        if (self == document) {

            NSAssert([NSThread isMainThread], @"Calling %s from a background thread is not supported!", __func__);

            [self closeConnection];

            // Unregister observers
            [self _removePreferenceObservers];

            [[NSNotificationCenter defaultCenter] removeObserver:self];
            [NSObject cancelPreviousPerformRequestsWithTarget:self];

            [taskProgressWindow close];

            if (processListController) [processListController close];

            // #2924: The connection controller doesn't retain its delegate (us), but it may outlive us (e.g. when running a bg thread)
            [connectionController setDelegate:nil];
            [printWebView setFrameLoadDelegate:nil];

            if (taskDrawTimer) {
                [taskDrawTimer invalidate];
            }
            if (queryExecutionTimer) {
                [queryExecutionTimer invalidate];
            }
        }
    }
}

#pragma mark -

- (void)dealloc {
    NSLog(@"Dealloc called %s", __FILE_NAME__);
}

@end

