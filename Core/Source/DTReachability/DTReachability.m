//
//  DTReachability.m
//  AutoIngest
//
//  Created by Oliver Drobnik on 29.04.13.
//  Copyright (c) 2013 Cocoanetics. All rights reserved.
//

#import "DTReachability.h"
#import "DTLog.h"

#import <arpa/inet.h>

@implementation DTReachability
{
	NSMutableSet *_observers;
	SCNetworkReachabilityRef _reachability;
	SCNetworkConnectionFlags _connectionFlags;
	NSString *_hostname;
}


static DTReachability *_sharedInstance;

+ (DTReachability *)defaultReachability
{
	static dispatch_once_t instanceOnceToken;
	
	dispatch_once(&instanceOnceToken, ^{
		_sharedInstance = [[DTReachability alloc] init];
	});
	
	return _sharedInstance;
}

- (instancetype)init
{
	return [self initWithHostname:@"apple.com"];
}

- (instancetype) initWithHostname:(NSString *)hostname
{
	self = [super init];
	
	if (self)
	{
		_observers = [[NSMutableSet alloc] init];
		_hostname = hostname;
	}
	return self;
}

- (void)dealloc
{
	[self _unregisterNetworkReachability];
}

- (id)addReachabilityObserverWithBlock:(void(^)(SCNetworkConnectionFlags connectionFlags))observer
{
	@synchronized(self)
	{
		// copy the block
		DTReachabilityObserverBlock block = [observer copy];
		
		// add it to the observers
		[_observers addObject:block];
		
		[self _registerNetworkReachability];
				
	
		// get the current flags if possible
		if (SCNetworkReachabilityGetFlags(_reachability, &_connectionFlags))
		{
			block(_connectionFlags);
		}
		
		return block;
	}
}

- (void)removeReachabilityObserver:(id)observer
{
	@synchronized(self)
	{
		[_observers removeObject:observer];
		
		// if this was the last we don't need the reachability no longer
		
		if (![_observers count])
		{
			[self _unregisterNetworkReachability];
		}
	}
}

+ (id)addReachabilityObserverWithBlock:(void(^)(SCNetworkConnectionFlags connectionFlags))observer
{
	return [[DTReachability defaultReachability] addReachabilityObserverWithBlock:observer];
}

+ (void)removeReachabilityObserver:(id)observer
{
	return [[DTReachability defaultReachability] removeReachabilityObserver:observer];
}

- (void)setHostname:(NSString *)hostname {
	@synchronized(self) {
		if (![hostname isEqualToString:_hostname])
		{
			[self _unregisterNetworkReachability];
			_hostname = hostname;
			[self _registerNetworkReachability];
		}
	}
}

#pragma mark - Internals

- (void)_registerNetworkReachability {
	// first watcher creates reachability
	if (!_reachability)
	{
		_reachability = SCNetworkReachabilityCreateWithName(kCFAllocatorDefault, [_hostname UTF8String]);
	
		SCNetworkReachabilityContext context = {0, (__bridge void *)_observers, NULL, NULL, NULL};
	
		if(SCNetworkReachabilitySetCallback(_reachability, DTReachabilityCallback, &context))
		{
			if(!SCNetworkReachabilityScheduleWithRunLoop(_reachability, CFRunLoopGetMain(), kCFRunLoopCommonModes))
			{
				DTLogError(@"Error: Could not schedule reachability");
				SCNetworkReachabilitySetCallback(_reachability, NULL, NULL);
			}
		}
	}
}

- (void)_unregisterNetworkReachability {
	SCNetworkReachabilitySetCallback(_reachability, NULL, NULL);
	
	if (SCNetworkReachabilityUnscheduleFromRunLoop(_reachability, CFRunLoopGetMain(), kCFRunLoopCommonModes))
	{
		DTLogInfo(@"Unscheduled reachability");
	}
	else
	{
		DTLogError(@"Error: Could not unschedule reachability");
	}
	
	_reachability = nil;

}

- (void)_notifyObserversWithFlags:(SCNetworkConnectionFlags)flags
{
	@synchronized(self)
	{
		for (DTReachabilityObserverBlock observer in _observers)
		{
			observer(flags);
		}
	}
}

static void DTReachabilityCallback(SCNetworkReachabilityRef target, SCNetworkConnectionFlags flags, void *info)
{
	DTReachability *reachability = (__bridge DTReachability *)info;

	[reachability _notifyObserversWithFlags:flags];
}

@end
