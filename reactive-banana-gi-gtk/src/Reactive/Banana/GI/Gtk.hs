{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE ExistentialQuantification #-}

module Reactive.Banana.GI.Gtk
    ( BuilderCastException(..)
    , castB
    , signalAddHandler
    , signalEN
    , signalE0
    , signalE1
    , propE
    , propB
    , sink
    ) where

import Reactive.Banana
import Reactive.Banana.Frameworks

import Data.Typeable
import Control.Exception
import Control.Monad.IO.Class
import Data.Maybe (fromJust)
import qualified Data.Text as T
import Data.Text (Text)
import GHC.ForeignPtr (ForeignPtr(..))

import Data.GI.Base
import Data.GI.Base.Attributes
    ( AttrLabelProxy(..)
    , AttrInfo(..)
    , AttrLabel(..)
    , AttrGetC(..)
    )

import Data.GI.Base.Overloading
    ( ResolveAttribute(..)
    , HasAttributeList(..)
    )

import Data.GI.Base.Signals
    ( SignalInfo(..)
    , GObjectNotifySignalInfo(..)
    )
import GI.Gtk
    ( GObject
    , IsBuilder
    , builderGetObject
    , get
    )
import Data.GI.Base.ManagedPtr (unsafeCastTo)

-- | Thown when 'castB' fails get an object
data BuilderCastException = UnknownIdException String
    deriving (Show, Typeable)

instance Exception BuilderCastException

-- | Shortcut for getting 'Data.GI.Base.GObject' from a Builder
--
-- @
-- stack <- castB builder "stack" Stack
-- @
castB
    :: (IsBuilder a, GObject o, MonadIO m)
    => a
    -> Text
    -> (ForeignPtr o -> o)
    -> m o
castB builder ident gtype =
    liftIO $ do
        o <- builderGetObject builder ident
        case o of
            Just a -> unsafeCastTo gtype a
            Nothing ->
                throw $ UnknownIdException $ T.unpack ident

signalAddHandler
    ::
        ( SignalInfo info
        , GObject self
        )
    => self
    -> SignalProxy self info
    -> ((a -> IO ()) -> HaskellCallbackType info)
    -> IO (AddHandler a)
signalAddHandler self signal f = do
    (addHandler, fire) <- newAddHandler
    on self signal (f fire)
    return addHandler

-- | Create an 'Reactive.Banana.Event' from
-- a 'Data.GI.Base.Signals.SignalProxy'. For making signalE# functions.
signalEN
    ::
        ( SignalInfo info
        , GObject self
        )
    => self
    -> SignalProxy self info
    -> ((a -> IO ()) -> HaskellCallbackType info)
    -> MomentIO (Event a)
signalEN self signal f = do
    addHandler <- liftIO $ signalAddHandler self signal f
    fromAddHandler addHandler

-- | Get an 'Reactive.Banana.Event' from
-- a 'Data.GI.Base.Signals.SignalProxy' that produces nothing.
--
-- @
-- destroyE <- signalE1 window #destroy
-- @
signalE0
    ::
        ( HaskellCallbackType info ~ IO ()
        , SignalInfo info
        , GObject self
        )
    => self
    -> SignalProxy self info
    -> MomentIO (Event ())
signalE0 self signal =  signalEN self signal ($ ())

-- | Get an 'Reactive.Banana.Event' from
-- a 'Data.GI.Base.Signals.SignalProxy' that produces one argument.
signalE1
    ::
        ( HaskellCallbackType info ~ (a -> IO ())
        , SignalInfo info
        , GObject self
        )
    => self
    -> SignalProxy self info
    -> MomentIO (Event a)
signalE1 self signal = signalEN self signal id

-- | Get an 'Reactive.Banana.Event' from
-- a 'Data.GI.Base.Attributes.AttrLabelProxy' that produces one argument.
propE self attr = do
    e <- signalEN self (PropertyNotify attr) id
    (const $ get self attr) `mapEventIO` e

-- | stepper on 'propE'
propB self attr = do
    e <- propE self attr
    initV <- get self attr
    stepper initV e

sink self attr b = do
    x <- valueBLater b
    liftIOLater $ set self [attr := x]
    e <- changes b
    reactimate' $ (fmap $ \x -> set self [attr := x]) <$> e