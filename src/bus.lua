-- src/bus.lua
-- Synchronous publish/subscribe event bus (Principle 4). Systems communicate
-- only through this: a publisher names an event and hands over data; any number
-- of subscribers registered for that event are called, in subscription order.
-- No system holds a reference to another.
--
-- "Synchronous" means publish() runs the handlers immediately, before returning.
-- The interface (subscribe/publish/clear) hides that choice, so it could later
-- become a queued bus without any system changing.

local Bus = {}

-- event_name -> ordered list of handler functions
Bus.subscribers = {}

-- Register a handler for an event. Lazily creates the list the first time an
-- event is seen; appending keeps handlers in the order they subscribed.
function Bus.subscribe(event_name, handler)
    local list = Bus.subscribers[event_name]
    if not list then
        list = {}
        Bus.subscribers[event_name] = list
    end
    list[#list + 1] = handler
end

-- Fire an event: call every handler subscribed to it with `data`. An event with
-- no subscribers is a silent no-op -- publishers never need to know who listens.
function Bus.publish(event_name, data)
    local list = Bus.subscribers[event_name]
    if not list then return end
    for i = 1, #list do
        list[i](data)
    end
end

-- Drop all subscribers. Used by tests for isolation and on starting a new game.
function Bus.clear()
    Bus.subscribers = {}
end

return Bus
