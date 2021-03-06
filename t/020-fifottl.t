#!/usr/bin/env tarantool

-- vim: set ft=lua :

local fiber = require 'fiber'
local test = (require 'tap').test()
local tnt  = require 't.tnt'
local state = require 'queue.abstract.state'
test:plan(9)

local queue = require 'queue.abstract'
test:ok(queue.start(), 'queue.start()')
test:ok(queue, 'queue is loaded')

local tube = queue.create_tube('test', 'fifottl')
test:ok(tube, 'test tube created')
test:is(tube.name, 'test', 'tube.name')
test:is(tube.type, 'fifottl', 'tube.type')


test:test('put/take/peek', function(test)
    test:plan(11)

    local task = tube:put('abc')

    test:ok(task, "task was put")
    test:is(task[2], state.READY, "task.state")
    
    local peek = tube:peek(task[1])
    test:is_deeply(task[1], peek[1], "put and peek tasks are the same")
    test:is_deeply(task[2], peek[2], "put and peek tasks are the same")
    test:is_deeply(task[3], peek[3], "put and peek tasks are the same")

    local taken = tube:take{ timeout =  .1 }
    test:ok(taken, 'task was taken')

    test:is(task[1], taken[1], 'task.id')
    test:is(taken[2], state.TAKEN, 'task.status')
    
    local ack = tube:ack(taken[1])
    test:ok(ack, 'task was acked')

    local s, e = pcall(function() tube:peek(task[1]) end)
    test:ok(not s, "peek status")
    test:ok(string.match(e, 'Task %d+ not found') ~= nil, 'peek error message')
end)

test:test('delayed tasks', function(test)
    test:plan(12)

    local task = tube:put('cde', { delay = 0.1, ttl = 0.1, ttr = 0.01 })
    test:ok(task, 'delayed task was put')
    test:is(task[3], 'cde', 'task.data')
    test:is(task[2], state.DELAYED, 'state is DELAYED')

    test:isnil(tube:take(.01), 'delayed task was not taken')

    local taken = tube:take(.15)
    test:ok(taken, 'delayed task was taken after timeout')
    test:is(taken[3], 'cde', 'task.data')

    local retaken = tube:take(0.05)
    test:ok(retaken, "retake task after ttr")
    test:is(retaken[3], 'cde', 'task.data')

    fiber.sleep(0.2)
    local s, e = pcall(function() tube:peek(retaken[1]) end)
    test:ok(not s, 'Task is not in database (TTL)')
    test:ok(string.match(e, 'Task %d+ not found') ~= nil, 'peek error message')


    s, e = pcall(function() tube:ack(retaken[1]) end)
    test:ok(not s, 'Task is not ackable (TTL)')
    test:ok(string.match(e, 'Task was not taken') ~= nil, 'peek error message')
end)

test:test('delete/peek', function(test)
    test:plan(10)

    local task = tube:put('abc')
    test:ok(task, 'task was put')
    test:is(task[2], state.READY, 'task is READY')

    local taken = tube:take(.1)
    test:ok(taken, 'task was taken')
    test:is(taken[3], 'abc', 'task.data')
    test:is(taken[2], state.TAKEN, 'task is really taken')

    local removed = tube:delete(task[1])
    test:ok(removed, 'tube:delete')
    test:is(removed[3], 'abc', 'removed.data')
    test:is(removed[2], state.DONE, 'removed.status')

    local s, e = pcall(function() tube:ack(task[1]) end)
    test:ok(not s, "Can't ack removed task")
    test:ok(string.match(e, 'Task was not taken') ~= nil, 'peek error message')
end)

test:test('bury/peek/kick', function(test)
    test:plan(17)

    local task = tube:put('abc')
    test:ok(task, 'task was put')
    test:is(task[2], state.READY, 'task is READY')

    local taken = tube:take(.1)
    test:ok(taken, 'task was taken')
    test:is(taken[3], 'abc', 'task.data')
    test:is(taken[2], state.TAKEN, 'task is really taken')

    local buried = tube:bury(task[1])
    test:ok(buried, 'tube:bury')
    test:is(buried[3], 'abc', 'buried.data')
    test:is(buried[2], state.BURIED, 'buried.status')

    local s, e = pcall(function() tube:ack(task[1]) end)
    test:ok(not s, "Can't ack removed task")
    test:ok(string.match(e, 'Task was not taken') ~= nil, 'peek error message')

    local peek = tube:peek(task[1])
    test:is(peek[1], buried[1], 'task was peek')
    test:is(peek[2], buried[2], 'task.status')
    test:is(peek[3], buried[3], 'task.data')

    fiber.create(function()
        local retaken = tube:take(0.1)
        test:ok(retaken, 'buried task was retaken')

        test:is(retaken[1], buried[1], 'task.id')
        test:is(retaken[2], state.TAKEN, 'task.status')
        test:is(retaken[3], buried[3], 'task.data')
    end)

    tube:kick(1)
    fiber.sleep(0.1)
end)

test:check()
tnt.finish()
os.exit(0)

