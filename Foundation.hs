-- Copyright © 2014 Bart Massey
-- Based on material Copyright © 2013 School of Haskell
-- https://www.fpcomplete.com/school/advanced-haskell/
--   building-a-file-hosting-service-in-yesod

-- This work is made available under the "GNU AGPL v3", as
-- specified the terms in the file COPYING in this
-- distribution.

{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

module Foundation where

import Control.Concurrent.STM
import Data.ByteString.Lazy (ByteString)

import Data.Char
import Data.Default
import Data.Map (Map)
import qualified Data.Map as M
import Text.Hamlet
import Yesod
import Yesod.Default.Util

data Filetype = FiletypeText | FiletypeImage | FiletypeOther
                deriving Eq

data FileAssoc = FileAssoc { fileAssocId :: !Int,
                             fileAssocName :: !String,
                             fileAssocContents :: !ByteString,
                             fileAssocMime :: !String,
                             fileAssocType :: !Filetype }

data App = App { appNextId :: !(TVar Int),
                 appGalleries :: !(TVar (Map Int FileAssoc)) }

instance Yesod App where
  defaultLayout widget = do
    let wf = $(widgetFileNoReload def "default-layout")
    pageContent <- widgetToPageContent wf
    withUrlRenderer $(hamletFile "templates/default-layout-wrapper.hamlet")

instance RenderMessage App FormMessage where
    renderMessage _ _ = defaultFormMessage

mkYesodData "App" $(parseRoutesFile "config/routes")

getFAList :: Handler [FileAssoc]
getFAList = do
  state <- getYesod
  galleryMap <- liftIO $ readTVarIO $ appGalleries state
  return $ M.elems galleryMap

addFile :: App -> FileAssoc -> Handler ()
addFile state op = do
  faid <- getNextId state
  let op' = op { fileAssocId = faid }
  liftIO $ atomically $
    modifyTVar (appGalleries state) (M.insert faid op')

getById :: Int -> Handler FileAssoc
getById faid = do
  state <- getYesod
  fileAssocs <- liftIO $ readTVarIO $ appGalleries state
  case M.lookup faid fileAssocs of
    Just fa -> return fa
    _ -> notFound

getNextId :: App -> Handler Int
getNextId state = do
    nid <- liftIO $ atomically $ rmwNextId $ appNextId state
    return nid
    where
      rmwNextId tvar = do
        nextId <- readTVar tvar
        writeTVar tvar (nextId + 1)
        return nextId

parseFiletype :: String -> Filetype
parseFiletype mime =
    case break (== '/') mime of
      (_, "") -> FiletypeOther
      (field, _) ->
          case map toLower field of
            "text" -> FiletypeText
            "image" -> FiletypeImage
            _ -> FiletypeOther
