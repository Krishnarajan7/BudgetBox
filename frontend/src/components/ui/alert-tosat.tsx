import * as React from "react";
import { cva, type VariantProps } from "class-variance-authority";
import { motion } from "framer-motion";
import { cn } from "@/lib/utils";
import {
  CheckCircle2,
  AlertTriangle,
  Info,
  XOctagon,
  X,
} from "lucide-react";

// Define variants for the alert toast using cva
const alertToastVariants = cva(
  "relative w-full max-w-sm overflow-hidden rounded-lg shadow-lg flex items-start p-4 space-x-4",
  {
    variants: {
      variant: {
        success: "",
        warning: "",
        info: "",
        error: "",
      },
      styleVariant: {
        default: "bg-background border",
        filled: "",
      },
    },
    compoundVariants: [
      {
        variant: "success",
        styleVariant: "default",
        className: "text-success-foreground border-success/30",
      },
      {
        variant: "warning",
        styleVariant: "default",
        className: "text-warning-foreground border-warning/30",
      },
      {
        variant: "info",
        styleVariant: "default",
        className: "text-info-foreground border-info/30",
      },
      {
        variant: "error",
        styleVariant: "default",
        className: "text-destructive-foreground border-destructive/30",
      },
      {
        variant: "success",
        styleVariant: "filled",
        className: "bg-success text-success-foreground",
      },
      {
        variant: "warning",
        styleVariant: "filled",
        className: "bg-warning text-warning-foreground",
      },
      {
        variant: "info",
        styleVariant: "filled",
        className: "bg-info text-info-foreground",
      },
      {
        variant: "error",
        styleVariant: "filled",
        className: "bg-destructive text-destructive-foreground",
      },
    ],
    defaultVariants: {
      variant: "info",
      styleVariant: "default",
    },
  }
);

// Define icon map for different variants
const iconMap = {
  success: CheckCircle2,
  warning: AlertTriangle,
  info: Info,
  error: XOctagon,
};

// Define icon color classes
const iconColorClasses: Record<string, Record<string, string>> = {
  default: {
    success: "text-success",
    warning: "text-warning",
    info: "text-info",
    error: "text-destructive",
  },
  filled: {
    success: "text-success-foreground",
    warning: "text-warning-foreground",
    info: "text-info-foreground",
    error: "text-destructive-foreground",
  },
};

export interface AlertToastProps
  extends VariantProps<typeof alertToastVariants> {
  /** The title of the alert. */
  title: string;
  /** A more detailed description for the alert. */
  description: string;
  /** A function to call when the alert is dismissed. */
  onClose: () => void;
  /** Additional class names */
  className?: string;
}

const AlertToast = React.forwardRef<HTMLDivElement, AlertToastProps>(
  ({ className, variant = 'info', styleVariant = 'default', title, description, onClose }, ref) => {
    const Icon = iconMap[variant!];

    return (
      <motion.div
        ref={ref}
        role="alert"
        layout
        initial={{ opacity: 0, y: 50, scale: 0.3 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        exit={{ opacity: 0, y: 20, scale: 0.5 }}
        transition={{
          type: "spring",
          stiffness: 260,
          damping: 20,
        }}
        className={cn(alertToastVariants({ variant, styleVariant }), className)}
      >
        {/* Icon */}
        <div className="flex-shrink-0">
          <Icon className={cn("h-6 w-6", iconColorClasses[styleVariant!][variant!])} aria-hidden="true" />
        </div>

        {/* Content */}
        <div className="flex-1">
          <p className="text-sm font-semibold">{title}</p>
          <p className="text-sm opacity-90">{description}</p>
        </div>
        
        {/* Close Button */}
        <div className="flex-shrink-0">
          <button
            onClick={onClose}
            aria-label="Close"
            className={cn(
              "p-1 rounded-full opacity-80 hover:opacity-100 focus:outline-none focus:ring-2 focus:ring-offset-2",
              styleVariant === 'default' ? "text-foreground/70 hover:bg-muted" : "hover:bg-black/20"
            )}
          >
            <X className="h-5 w-5" />
          </button>
        </div>
      </motion.div>
    );
  }
);

AlertToast.displayName = "AlertToast";

export { AlertToast, alertToastVariants };