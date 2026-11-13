package com.airsim.phonecontrol;

import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;

/** Bounded tombstones prevent the inbox fallback from resurrecting acknowledged SMS. */
final class SMSRecentDeliveryIDs {
    private static final int MAX_IDS = 512;
    private final LinkedHashSet<String> ids = new LinkedHashSet<>();

    SMSRecentDeliveryIDs(Collection<String> previous) {
        for (String id : previous) remember(id);
    }

    boolean contains(String id) { return ids.contains(id); }

    void remember(String id) {
        if (id == null || id.isEmpty()) return;
        ids.remove(id);
        ids.add(id);
        while (ids.size() > MAX_IDS) ids.remove(ids.iterator().next());
    }

    List<String> snapshot() { return new ArrayList<>(ids); }
}
