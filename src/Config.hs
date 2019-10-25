{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Config
    ( Config(..)
    , homeDir
    , inboxDirs
    , libraryDir
    , importAction
    , ImportAction(..)
    , wordSeparator
    , tryGetConfig
    , defaultConfig
    , createConfig
    , getConfigPath
    ) where

import qualified Control.Exception as E
import           Data.Function ((&))
import           Data.Ini.Config.Bidir (Ini, IniSpec, (.=))
import qualified Data.Ini.Config.Bidir as C
import           Data.Text (Text)
import qualified Data.Text.IO as TIO
import           Lens.Micro ((^.), (.~))
import           Lens.Micro.TH (makeLenses)
import           Path (Abs, Dir, File, Path, Rel, (</>))
import qualified Path
import qualified Path.IO as Path


data Config = Config
    { _homeDir      :: Path Abs Dir
    , _inboxDirs    :: [Path Abs Dir]
    , _libraryDir   :: Path Abs Dir
    , _importAction :: ImportAction
    , _wordSeparator:: Text
    }


data ImportAction
    = Move | Copy


data ConfigData = ConfigData
    { _inboxDirsD  :: [FilePath]
    , _libraryDirD :: FilePath
    , _importMove  :: Bool
    , _wordSeparatorD :: Text
    } deriving Show


makeLenses ''Config
makeLenses ''ConfigData


defaultConfigData :: ConfigData
defaultConfigData =
    ConfigData
        { _inboxDirsD= ["Downloads"]
        , _libraryDirD = "papers"
        , _importMove = True
        , _wordSeparatorD = "_"
        }


defaultConfig :: IO Config
defaultConfig = readConfigData defaultConfigData


createConfig :: Path Abs File -> IO ()
createConfig cpath = do
    _ <- Path.ensureDir (Path.parent cpath)
    TIO.writeFile (Path.fromAbsFile cpath) configContent
    where
        configContent =
            C.serializeIni $ C.ini defaultConfigData configSpec


tryGetConfig :: Path Abs File -> IO (Either String Config)
tryGetConfig configPath = do
    configTxtResult <-
        E.tryJust displayErr $ TIO.readFile (Path.fromAbsFile configPath)

    let
        configIniResult =
            configTxtResult >>= (\t -> C.parseIni t configIni)

        configDataResult =
            C.getIniValue <$> configIniResult

        -- special case: allow " " in the .ini to be interpreted as
        -- a single space. Ugly but neceessary.
        inferSpace :: Config -> Config
        inferSpace conf =
            if conf ^. wordSeparator == "\" \""
                then conf & wordSeparator .~ " "
                else conf
    configResult <- sequence $ readConfigData <$> configDataResult
    pure $ inferSpace <$> configResult


readConfigData :: ConfigData -> IO Config
readConfigData configData = do
    home <- Path.getHomeDir
    inbDir <- mapM (Path.resolveDir home) (configData ^. inboxDirsD)
    libDir <- Path.resolveDir home (configData ^. libraryDirD)

    let action = if configData ^. importMove then Move else Copy
    let wordSep = configData ^. wordSeparatorD

    pure Config
        { _homeDir = home
        , _inboxDirs = inbDir
        , _libraryDir = libDir
        , _importAction = action
        , _wordSeparator = wordSep
        }


configSpec :: IniSpec ConfigData ()
configSpec =
    C.section "PAPERBOY" $ do
        inboxDirsD .=  C.field "inbox" (C.listWithSeparator "," C.string)
            & C.comment
                [ "The folder to watch for incoming files."
                , "Paths are relative to your home directory, but absolute paths are valid too."
                , "I will watch multiple folders if you give me a comma-separated list."
                ]

        libraryDirD .=  C.field "library" C.string
            & C.comment [ "The folder to copy/move renamed files to." ]

        importMove .=  C.field "move" C.bool
            & C.comment
                [ "Whether to move imported files."
                , "If set to false it will leave the original file unchanged."
                ]

        wordSeparatorD .=  C.field "wordseparator" C.text
            & C.comment
                [ "The character to insert between words."
                , "Write \" \" for space."
                ]


configIni :: Ini ConfigData
configIni = C.ini defaultConfigData configSpec


displayErr :: E.SomeException -> Maybe String
displayErr e =
    Just $ E.displayException e


configFile :: Path Rel File
configFile = $(Path.mkRelFile "pboy/pboy.ini")


getConfigPath :: IO (Path Abs File)
getConfigPath = do
    configHome <- Path.getXdgDir Path.XdgConfig Nothing
    pure $ configHome </> configFile
