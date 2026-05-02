"use client";

import {
  cloneElement,
  isValidElement,
  useEffect,
  useRef,
  useState,
  type ReactElement,
} from "react";

interface ChartElementProps {
  height?: number;
  width?: number;
}

interface ChartContainerProps {
  children: ReactElement<ChartElementProps>;
  height: number;
  className?: string;
}

export function ChartContainer({ children, height, className = "mt-4" }: ChartContainerProps) {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);

  useEffect(() => {
    const element = ref.current;
    if (!element) return;

    const update = () => {
      setWidth(Math.floor(element.getBoundingClientRect().width));
    };

    update();
    const observer = new ResizeObserver(update);
    observer.observe(element);

    return () => observer.disconnect();
  }, []);

  return (
    <div ref={ref} className={`w-full min-w-0 ${className}`} style={{ height }}>
      {width > 0 && isValidElement<ChartElementProps>(children)
        ? cloneElement(children, { width, height })
        : null}
    </div>
  );
}
