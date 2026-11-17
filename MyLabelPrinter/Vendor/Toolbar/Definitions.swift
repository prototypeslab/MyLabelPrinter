import Cocoa

extension NSStoryboard.SceneIdentifier
{
    static let customTitlebarAccessoryViewController = NSStoryboard.SceneIdentifier("CustomTitlebarAccessoryViewController")
}

extension NSToolbar.Identifier
{
    static let mainWindowToolbarIdentifier = NSToolbar.Identifier("MainWindowToolbar")
}

extension NSToolbarItem.Identifier
{
    static let toolbarItemToggleTitlebarAccessory = NSToolbarItem.Identifier("ToolbarToggleTitlebarAccessoryItem")
    
    static let toolbarItemMoreInfo = NSToolbarItem.Identifier("ToolbarMoreInfoItem")
    static let toolbarItemUserAccounts = NSToolbarItem.Identifier("ToolbarUserAccountsItem")
    
    static let toolbarMoreActions = NSToolbarItem.Identifier("ToolbarMoreActionsItem")

    static let toolbarShareButtonItem = NSToolbarItem.Identifier(rawValue: "ToolbarShareButtonItem")

    static let toolbarPickerItem = NSToolbarItem.Identifier("ToolbarPickerItemGroup")
    
    static let toolbarSearchItem = NSToolbarItem.Identifier("ToolbarSearchItem")
  
  
  static let toolbarItemNew = NSToolbarItem.Identifier("toolbarItemNew")
  static let toolbarItemOpen = NSToolbarItem.Identifier("toolbarItemOpen")
  static let toolbarItemSave = NSToolbarItem.Identifier("toolbarItemSave")
  static let toolbarItemPrint = NSToolbarItem.Identifier("toolbarItemPrint")
  static let toolbarItemObjectOrder = NSToolbarItem.Identifier("toolbarItemObjectOrder")
  static let toolbarItemZoom = NSToolbarItem.Identifier("toolbarItemZoom")
  static let toolbarItemTextBox = NSToolbarItem.Identifier("toolbarItemTextBox")
  static let toolbarItemFrame = NSToolbarItem.Identifier("toolbarItemFrame")
  static let toolbarItemImage = NSToolbarItem.Identifier("toolbarItemImage")
  static let toolbarItemSymbol = NSToolbarItem.Identifier("toolbarItemSymbol")
  static let toolbarItemClipArt = NSToolbarItem.Identifier("toolbarItemClipArt")
  static let toolbarItemShape = NSToolbarItem.Identifier("toolbarItemShape")
  static let toolbarItemLine = NSToolbarItem.Identifier("toolbarItemLine")
  static let toolbarItemBarcode = NSToolbarItem.Identifier("toolbarItemBarcode")
  static let toolbarItemDatabase = NSToolbarItem.Identifier("toolbarItemDatabase")
  
  
    static let toolbarItemSettings = NSToolbarItem.Identifier("toolbarItemSettings")
    static let toolbarItemExit = NSToolbarItem.Identifier("ToolbarExitItem")
}
