package com.balancerobot.repository;

import com.balancerobot.entity.TelemetryData;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface TelemetryRepository extends JpaRepository<TelemetryData, Long> {
    List<TelemetryData> findByDeviceIdAndRecordedAtBetweenOrderByRecordedAtDesc(
            Long deviceId, LocalDateTime from, LocalDateTime to);

    List<TelemetryData> findByDeviceIdOrderByRecordedAtDesc(Long deviceId, Pageable pageable);

    Optional<TelemetryData> findFirstByDeviceIdOrderByRecordedAtDesc(Long deviceId);

    void deleteByRecordedAtBefore(LocalDateTime cutoff);
}
